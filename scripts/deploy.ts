import { ethers } from "hardhat";

async function main() {
    const Sniper = await ethers.getContractFactory("UniversalSniper");
    const sniper = await Sniper.deploy();

    await sniper.deployed();

    console.log(`Sniper contract deployed to ${sniper.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
