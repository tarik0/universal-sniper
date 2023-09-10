import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import {expect} from "chai";
import {UniversalSniper} from "../typechain-types";
import {BigNumber, Signer} from "ethers";

/// WETH9 address at ethereum mainnet.
const WETH_ADDR = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

/// USDT address at ethereum mainnet.
const USDT_ADDR = "0xdac17f958d2ee523a2206206994597c13d831ec7";

/// DAI address at ethereum mainnet.
const DAI_ADDR = "0x6b175474e89094c44da98b954eedeac495271d0f";

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

        const tx = await sniper.execute([command], [inputs]);
        const receipt = await tx.wait(1);
        return {
            address: await computeVaultAddress(sniper, token, id.toNumber()),
            receipt
        };
    }

    /// Wrap ethers.
    async function wrapEthers(signer: Signer, amount: BigNumber) {
        const weth = await ethers.getContractAt("IWETH9", WETH_ADDR);
        await weth.connect(signer).deposit({ value: amount });
    }

    /// Buys V2 tokens.
    async function buyV2(sniper: UniversalSniper, amount: BigNumber, maxAmount: BigNumber, vaultCount: number) {
        // The factories.
        const factories = [
            "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f", // Uniswap V2
            "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac", // Sushiswap
        ]

        // The pool init codes.
        const initCodes = [
            "0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f",
            "0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303"
        ]

        // The path.
        const path = [
            WETH_ADDR,
            USDT_ADDR,
            DAI_ADDR
        ]

        // Create vaults.
        const vaults = (
            await Promise.all(
                [...Array(vaultCount).keys()]
                    .slice(0)
                    .map((i) => createVault(sniper, DAI_ADDR, BigNumber.from(i)))
            )
        ).map(({ address }) => address);

        // Execute BUY_V2.
        const command = "0x03"; // BUY_V2 command
        const inputs = ethers.utils.defaultAbiCoder.encode(
            ["uint256", "uint256", "address[]", "address[]", "address[]", "bytes[]"],
            [amount, maxAmount, vaults, path, factories, initCodes]
        );

        // Execute the command.
        const tx = await sniper.execute([command], [inputs], { value: amount });
        return { vaults, receipt: await tx.wait(1), path, factories, initCodes };
    }

    /// Buys V3 tokens.
    async function buyV3(sniper: UniversalSniper, amount: BigNumber, maxAmount: BigNumber, vaultCount: number) {
        // Factory.
        const factory = ethers.utils.getAddress("0x1f98431c8ad98523631ae4a59f267346ea31f984");
        const initCode = "0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54";

        // The path.
        const path = [
            WETH_ADDR,
            USDT_ADDR,
            DAI_ADDR
        ]

        // Create vaults.
        const vaults = (
            await Promise.all(
                [...Array(vaultCount).keys()]
                    .slice(0)
                    .map((i) => createVault(sniper, DAI_ADDR, BigNumber.from(i)))
            )
        ).map(({ address }) => address);

        // Execute BUY_V3.
        const command = "0x05"; // BUY_V3 command
        const inputs = ethers.utils.defaultAbiCoder.encode(
            ["uint256", "uint256", "address", "address[]", "address[]", "bytes"],
            [amount, maxAmount, factory, vaults, path, initCode]
        );

        // Execute the command.
        const tx = await sniper.execute([command], [inputs], { value: amount });
        return { vaults, receipt: await tx.wait(1), path, factory, initCode };
    }

    /// The deployment tests.
    describe("Deployment", () => {
        it("should deploy and set owner and version", async () => {
            const { sniper, owner } = await loadFixture(deploySniperFixture);
            await expect(await sniper.owner()).to.equal(owner.address);
            await expect(await sniper.version()).to.equal(6);
        });
    });

    /// The view commands.
    describe("View Commands", () => {
        it("should compute the vault addresses", async () => {
            const { sniper, owner } = await loadFixture(deploySniperFixture);
            const command = "0x00"; // COMPUTE_VAULT_ADDRESS
            const inputs = ethers.utils.defaultAbiCoder.encode(
                ["address", "uint256"],
                [ethers.constants.AddressZero, 0]
            );

            const addr = await computeVaultAddress(sniper, ethers.constants.AddressZero, 0);
            const response = await sniper.connect(owner).readView([command], [inputs]);
            const parsed = ethers.utils.defaultAbiCoder.decode(["address"], ethers.utils.arrayify(response[0]));
            await expect(parsed[0]).to.eq(addr);
        })

        it("should compute V2 swap price", async () => {
            // The factories.
            const factories = [
                "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f", // Uniswap V2
                "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac", // Sushiswap
            ]

            // The pool init codes.
            const initCodes = [
                "0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f",
                "0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303"
            ]

            // The path.
            const path = [
                DAI_ADDR,
                USDT_ADDR,
                WETH_ADDR
            ]

            // Encode & call.
            const { sniper, owner } = await loadFixture(deploySniperFixture);
            const command = "0x01"; // ASSET_V2_PRICE
            const inputs = ethers.utils.defaultAbiCoder.encode(
                ["address[]", "address[]", "bytes[]"],
                [path, factories, initCodes]
            );

            const response = await sniper.connect(owner).readView([command], [inputs]);
            const parsed = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], ethers.utils.arrayify(response[0]));
            await expect(parsed[0].toString()).to.not.eq("0");
        })

        it("should compute V3 swap price", async () => {
            // Factory.
            const factory = ethers.utils.getAddress("0x1f98431c8ad98523631ae4a59f267346ea31f984");
            const initCode = "0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54";

            // The path.
            const path = [
                WETH_ADDR,
                USDT_ADDR,
                DAI_ADDR
            ]

            // Encode & call.
            const { sniper, owner } = await loadFixture(deploySniperFixture);
            const command = "0x02"; // ASSET_V2_PRICE
            const inputs = ethers.utils.defaultAbiCoder.encode(
                ["address", "address[]", "bytes"],
                [factory, path, initCode]
            );

            const response = await sniper.connect(owner).readView([command], [inputs]);
            const parsed = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], ethers.utils.arrayify(response[0]));
            await expect(parsed[0].toString()).to.not.eq("0");
        })

        it("should return zero for unsupported commands", async () => {
            const { sniper, owner } = await loadFixture(deploySniperFixture);
            const unsupportedCommand = "0x99"; // Unsupported command
            const inputs = ethers.utils.defaultAbiCoder.encode(["address"], [ethers.constants.AddressZero]);

            const response = await sniper.connect(owner).readView([unsupportedCommand], [inputs]);
            await expect(response[0]).to.eq("0x0000000000000000000000000000000000000000");
        })
    })

    /// The command tests.
    describe("Commands", () => {
        it("should create new vault with `CREATE_VAULT` command", async () => {
            const { sniper } = await loadFixture(deploySniperFixture);
            const token = ethers.constants.AddressZero; // replace with actual token address
            const id = ethers.BigNumber.from(1);

            const {address, receipt} = await createVault(sniper, token, id);
            await expect(await ethers.provider.getCode(address)).to.not.equal("0x");
            console.log(`Vault create cost: ${receipt.gasUsed}`);
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
            const tx = await sniper.connect(owner).execute([command], [inputs], { value: bribe });

            // The block reward.
            const blockReward = "30512000000000";

            // Get the balance of the coinbase after the transaction
            const balanceAfter = await ethers.provider.getBalance(coinbase);

            // Check if the balance of the coinbase has increased by the bribe amount plus the block reward
            expect(balanceAfter.sub(balanceBefore)).to.gte(bribe.add(blockReward));

            console.log(`MEV bribe cost: ${(await tx.wait(1)).gasUsed}`);
        });

        it("should transfer funds from vault with `TRANSFER_FROM_VAULT` command", async () => {
            const { sniper, owner } = await loadFixture(deploySniperFixture);

            // Generate two vaults.
            const { address: vaultOne } = await createVault(sniper, WETH_ADDR, BigNumber.from(1));
            const { address: vaultTwo } = await createVault(sniper, WETH_ADDR, BigNumber.from(2));

            // Wrap ethers.
            const amount = ethers.utils.parseEther("1");
            await wrapEthers(owner, amount);

            // Transfer WETH to the first vault.
            const wethErc = await ethers.getContractAt("IERC20", WETH_ADDR);
            await wethErc.connect(owner).transfer(vaultOne, amount);

            // Execute TRANSFER_FROM_VAULT.
            const command = "0x02"; // TRANSFER_FROM_VAULT command
            const inputs = ethers.utils.defaultAbiCoder.encode(
                ["address", "address", "address"], [vaultOne, WETH_ADDR, vaultTwo]);

            // Execute the command.
            const tx = await sniper.execute([command], [inputs]);

            // Check the balance.
            const balance = await wethErc.balanceOf(vaultTwo)
            await expect(balance.eq(amount));

            console.log(`Transfer from vault cost: ${(await tx.wait()).gasUsed}`)
        })

        it("should buy tokens with `BUY_V2` command", async () => {
            const { sniper } = await loadFixture(deploySniperFixture);

            // Max 10 DAI output.
            const maxAmountsOut = ethers.utils.parseEther("50");
            const amountIn = ethers.utils.parseEther("1");

            // Execute BUY_V2.
            const {vaults, receipt} = await buyV2(sniper, amountIn, maxAmountsOut, 3)

            // after balances.
            const dai = await ethers.getContractAt("IERC20", DAI_ADDR);
            const balances = await Promise.all([
                dai.balanceOf(vaults[0]),
                dai.balanceOf(vaults[1]),
                dai.balanceOf(vaults[2]),
            ])

            expect(balances[0].eq(ethers.constants.Zero)).not.to.be.true;
            expect(balances[1].eq(ethers.constants.Zero)).not.to.be.true;
            expect(balances[2].eq(ethers.constants.Zero)).not.to.be.true;

            expect(balances[0].lt(maxAmountsOut)).to.be.true;
            expect(balances[1].lt(maxAmountsOut)).to.be.true;
            expect(balances[2].lt(maxAmountsOut)).to.be.true;

            console.log(`Avg. Buy V2 cost: ${receipt.gasUsed.div(vaults.length)}`)
        })

        it("should sell tokens with `SELL_V2` command", async () => {
            const { sniper, owner } = await loadFixture(deploySniperFixture);

            const maxAmountsOut = ethers.utils.parseEther("0");
            const amountIn = ethers.utils.parseEther("1");

            // Execute BUY_V2.
            const {vaults, path, factories, initCodes}
                = await buyV2(sniper, amountIn, maxAmountsOut, 3)

            // Reverse path.
            const sellPath = path.reverse();
            const sellPercentage = BigNumber.from("100");

            // Execute SELL_V2.
            const command = "0x04"; // SELL_V2 command
            const inputs = ethers.utils.defaultAbiCoder.encode(
                ["uint256", "address[]", "address[]", "address[]", "bytes[]"],
                [sellPercentage, vaults, sellPath, factories, initCodes]
            );

            // Before balance.
            const before = await sniper.provider.getBalance(await owner.getAddress());

            // Execute the command.
            const tx = await sniper.execute([command], [inputs]);
            const receipt = await tx.wait(1);

            // after balances.
            const dai = await ethers.getContractAt("IERC20", DAI_ADDR);
            const balances = await Promise.all([
                dai.balanceOf(vaults[0]),
                dai.balanceOf(vaults[1]),
                dai.balanceOf(vaults[2]),
            ])

            // after balance.
            const after = await sniper.provider.getBalance(await owner.getAddress());

            expect(balances[0].eq(ethers.constants.Zero)).to.be.true;
            expect(balances[1].eq(ethers.constants.Zero)).to.be.true;
            expect(balances[2].eq(ethers.constants.Zero)).to.be.true;
            expect(before.lt(after)).to.be.true;

            console.log(`Avg. Sell V2 cost: ${receipt.gasUsed.div(vaults.length)}`)
        })

        it("should buy tokens with `BUY_V3` command", async () => {
            const { sniper } = await loadFixture(deploySniperFixture);

            // Max 10 DAI output.
            const maxAmountsOut = ethers.utils.parseEther("50");
            const amountIn = ethers.utils.parseEther("1");

            // Execute BUY_V2.
            const {vaults, receipt} = await buyV3(sniper, amountIn, maxAmountsOut, 3)

            // after balances.
            const dai = await ethers.getContractAt("IERC20", DAI_ADDR);
            const balances = await Promise.all([
                dai.balanceOf(vaults[0]),
                dai.balanceOf(vaults[1]),
                dai.balanceOf(vaults[2]),
            ])

            expect(balances[0].eq(ethers.constants.Zero)).not.to.be.true;
            expect(balances[1].eq(ethers.constants.Zero)).not.to.be.true;
            expect(balances[2].eq(ethers.constants.Zero)).not.to.be.true;

            expect(balances[0].lt(maxAmountsOut)).to.be.true;
            expect(balances[1].lt(maxAmountsOut)).to.be.true;
            expect(balances[2].lt(maxAmountsOut)).to.be.true;

            console.log(`Avg. Buy V3 cost: ${receipt.gasUsed.div(vaults.length)}`)
        })

        it("should sell tokens with `SELL_V3` command", async () => {
            const { sniper, owner } = await loadFixture(deploySniperFixture);

            const maxAmountsOut = ethers.utils.parseEther("0");
            const amountIn = ethers.utils.parseEther("1");

            // Execute BUY_V2.
            const {vaults, path, factory, initCode}
                = await buyV3(sniper, amountIn, maxAmountsOut, 3)

            // Reverse path.
            const sellPath = path.reverse();
            const sellPercentage = BigNumber.from("100");

            // Execute SELL_V3.
            const command = "0x06"; // SELL_V3 command
            const inputs = ethers.utils.defaultAbiCoder.encode(
                ["uint256", "address", "address[]", "address[]", "bytes"],
                [sellPercentage, factory, vaults, sellPath, initCode]
            );

            // Before balance.
            const before = await sniper.provider.getBalance(await owner.getAddress());

            // Execute the command.
            const tx = await sniper.execute([command], [inputs]);
            const receipt = await tx.wait(1);

            // after balances.
            const dai = await ethers.getContractAt("IERC20", DAI_ADDR);
            const balances = await Promise.all([
                dai.balanceOf(vaults[0]),
                dai.balanceOf(vaults[1]),
                dai.balanceOf(vaults[2]),
            ])

            // after balance.
            const after = await sniper.provider.getBalance(await owner.getAddress());

            expect(balances[0].eq(ethers.constants.Zero)).to.be.true;
            expect(balances[1].eq(ethers.constants.Zero)).to.be.true;
            expect(balances[2].eq(ethers.constants.Zero)).to.be.true;
            expect(before.lt(after)).to.be.true;

            console.log(`Avg. Sell V3 cost: ${receipt.gasUsed.div(vaults.length)}`)
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
