import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import {expect} from "chai";
import {UniversalSniper} from "../typechain-types";
import {BigNumber, Signer} from "ethers";

/// WETH9 address at ethereum mainnet.
const WETH_ADDR = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

describe("UniversalSniper", function () {
    /// Deploy sniper and use the snapshot with `loadFixture`.
    async function deploySniperFixture() {
        // Contracts are deployed using the first signer/account by default
        const [owner, otherAccount] = await ethers.getSigners();

        const UniversalSniperFactory = await ethers.getContractFactory("UniversalSniper");
        const sniper = await UniversalSniperFactory.deploy();

        return { sniper, owner, otherAccount };
    }

    /// Compute the vault address.
    async function computeVaultAddress(sniper: UniversalSniper, token: string, id: number) {
        const VaultFactory = await ethers.getContractFactory("Vault");
        const bytecodeHash = ethers.utils.keccak256(VaultFactory.bytecode);

        const salt = ethers.utils.keccak256(ethers.utils.solidityPack(["address", "uint256"], [token, id]));
        const data = ethers.utils.keccak256(
            ethers.utils.concat([
                "0xff",
                sniper.address,
                salt,
                bytecodeHash
            ])
        );

        return ethers.utils.getAddress("0x" + data.slice(-40));
    }

    /// Generate a new vault.
    async function createVault(sniper: UniversalSniper, token: string, id: BigNumber) {
        const command = "0x00"; // CREATE_VAULT command
        const inputs = ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [token, id]);

        await sniper.execute([command], [inputs]);
        return await computeVaultAddress(sniper, token, id.toNumber());
    }

    /// Wrap ethers.
    async function wrapEthers(signer: Signer, amount: BigNumber) {
        const weth = await ethers.getContractAt("IWETH9", WETH_ADDR);
        await weth.connect(signer).deposit({ value: amount });
    }

    /// The deployment tests.
    describe("Deployment", () => {
        it("should deploy and set owner", async () => {
            const { sniper, owner } = await loadFixture(deploySniperFixture);
            await expect(await sniper.owner()).to.equal(owner.address);
        });
    });

    /// The command tests.
    describe("Commands", () => {
        it("should create new vault with `CREATE_VAULT` command", async () => {
            const { sniper, owner } = await loadFixture(deploySniperFixture);
            const token = ethers.constants.AddressZero; // replace with actual token address
            const id = ethers.BigNumber.from(1);

            const expectedVaultAddress = await createVault(sniper, token, id);
            await expect(await ethers.provider.getCode(expectedVaultAddress)).to.not.equal("0x");
        })

        it("should bribe the coinbase with `BRIBE_MEV` command", async () => {
            const { sniper, owner } = await loadFixture(deploySniperFixture);

            const bribe = ethers.utils.parseEther("1");
            const command = "0x01"; // BRIBE_MEV command
            const inputs = ethers.utils.defaultAbiCoder.encode(["uint256"], [bribe]);

            // Get the coinbase address from the configuration
            const coinbase = "0x000000000000000000000000000000000000dead";

            // Get the balance of the coinbase before the transaction
            const balanceBefore = await ethers.provider.getBalance(coinbase);

            // Execute the command with enough value to cover the bribe
            await sniper.connect(owner).execute([command], [inputs], { value: bribe });

            // The block reward.
            const blockReward = "30512000000000";

            // Get the balance of the coinbase after the transaction
            const balanceAfter = await ethers.provider.getBalance(coinbase);

            // Check if the balance of the coinbase has increased by the bribe amount plus the block reward
            expect(balanceAfter.sub(balanceBefore)).to.equal(bribe.add(blockReward));
        });

        it("should transfer funds from vault with `TRANSFER_FROM_VAULT` command", async () => {
            const { sniper, owner } = await loadFixture(deploySniperFixture);

            // Generate two vaults.
            const vaultOne = await createVault(sniper, WETH_ADDR, BigNumber.from(1));
            const vaultTwo = await createVault(sniper, WETH_ADDR, BigNumber.from(2));

            // Wrap ethers.
            const amount = ethers.utils.parseEther("1");
            await wrapEthers(owner, amount);

            // Transfer WETH to the first vault.
            const wethErc = await ethers.getContractAt("IERC20", WETH_ADDR);
            await wethErc.connect(owner).transfer(vaultOne, amount);

            // Execute TRANSFER_FROM_VAULT.
            const command = "0x02"; // BRIBE_MEV command
            const inputs = ethers.utils.defaultAbiCoder.encode(
                ["address", "address", "address"], [vaultOne, WETH_ADDR, vaultTwo]);

            // Execute the command.
            await sniper.execute([command], [inputs]);

            // Check the balance.
            const balance = await wethErc.balanceOf(vaultTwo)
            await expect(balance.eq(amount));
        })

        it("should revert for unsupported commands", async () => {
            const { sniper, owner } = await loadFixture(deploySniperFixture);
            const unsupportedCommand = "0x99"; // Unsupported command
            const inputs = ethers.utils.defaultAbiCoder.encode(["address"], [ethers.constants.AddressZero]);

            await expect(sniper.connect(owner).execute([unsupportedCommand], [inputs]))
                .to.be.reverted;
        })
    })
});
