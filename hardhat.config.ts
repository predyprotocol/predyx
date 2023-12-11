import * as dotenv from 'dotenv'
import fs from 'fs'

import { HardhatUserConfig, task } from 'hardhat/config'
import "@nomicfoundation/hardhat-verify"
import '@typechain/hardhat'
import 'hardhat-contract-sizer'
import 'hardhat-deploy'
import '@eth-optimism/hardhat-ovm'
import '@nomiclabs/hardhat-ethers'
import 'hardhat-preprocessor'

dotenv.config()

const InfuraKey = process.env.INFURA_API_KEY

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners()

  for (const account of accounts) {
    console.log(account.address)
  }
})

const config: HardhatUserConfig = {
  networks: {
    localhost: {
      url: 'http://127.0.0.1:7545',
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${InfuraKey}`,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${InfuraKey}`,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      //gas: 1000000000,
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${InfuraKey}`,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    xdai: {
      url: 'https://rpc.xdaichain.com/',
      gasPrice: 1000000000,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    matic: {
      url: 'https://rpc-mainnet.maticvigil.com/',
      gasPrice: 1000000000,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    arbitrum: {
      url: 'https://arb1.arbitrum.io/rpc',
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      companionNetworks: {
        l1: 'mainnet',
      },
    },
    goerliArbitrum: {
      url: 'https://goerli-rollup.arbitrum.io/rpc',
      gasPrice: 2000000000, // 0.2 gwei
      gas: 50_000_000,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      companionNetworks: {
        l1: 'goerli',
      },
    },
    kovanOptimism: {
      url: `https://optimism-kovan.infura.io/v3/${InfuraKey}`,
      gasPrice: 1000000000,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      ovm: true,
      companionNetworks: {
        l1: 'kovan',
      },
    },
    optimism: {
      url: `https://optimism-mainnet.infura.io/v3/${InfuraKey}`,
      gasPrice: 0,
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      ovm: true,
      companionNetworks: {
        l1: 'mainnet',
      },
    },
    "base-mainnet": {
      url: 'https://mainnet.base.org',
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 1000000000,
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.8.19',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  ovm: {
    solcVersion: '0.7.6',
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  etherscan: {
    apiKey: process.env.BASE_ETHERSCAN_KEY,
    customChains: [
      {
        network: "goerliArbitrum",
        chainId: 421613,
        urls: {
          apiURL: "https://api-testnet.arbiscan.io/api",
          browserURL: "https://testnet.arbiscan.io/",
        }
      }
    ]
  },
  preprocess: {
    eachLine: (hre) => ({
      transform: (line: string) => {
        if (line.match(/^\s*import /i)) {
          getRemappings().forEach(([find, replace]) => {
            if (line.match('"' + find)) {
              line = line.replace('"' + find, '"' + replace)
            } else if (line.match("'" + find)) {
              line = line.replace("'" + find, "'" + replace)
            }
          })
        }
        return line
      },
    }),
  },
  paths: {
    sources: './src',
    cache: './cache_hardhat',
  },
}

function getRemappings() {
  return fs
    .readFileSync('remappings.txt', 'utf8')
    .split('\n')
    .filter(Boolean) // remove empty lines
    .map((line: any) => line.trim().split('='))
}

export default config
