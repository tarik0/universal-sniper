import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter"

const ALCHEMY_KEY = "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1_000_000
      },
    }
  },
  networks: {
    hardhat: {
      coinbase: "0x000000000000000000000000000000000000dead",
      forking: {
        url: `https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`
      }
    }
  },
  gasReporter: {
    currency: "usd",
    enabled: true
  },
  mocha: {
    timeout: 60000,
  },
};

export default config;
