import {HardhatUserConfig} from "hardhat/config"
import "@nomicfoundation/hardhat-toolbox"
import "hardhat-abi-exporter"
import "hardhat-gas-reporter"
import "solidity-coverage"
import "dotenv/config"

const MAINNET_URL = process.env.MAINNET_URL || "https://rpc.ankr.com/polygon"

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  gasReporter: {
    showTimeSpent: true,
    currency: "USD",
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      forking: {
        url: MAINNET_URL,
        blockNumber: 50497520,
      },
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./contracts",
    tests: "./tests",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 200000,
  },
  // etherscan: {
  //   apiKey: `${process.env.ETHERSCAN_API_KEY}`,
  // },
  abiExporter: {
    path: "./abi",
    clear: true,
    flat: true,
    spacing: 2,
  },
  typechain: {
    outDir: "types",
    target: "ethers-v6",
  },
}

export default config
