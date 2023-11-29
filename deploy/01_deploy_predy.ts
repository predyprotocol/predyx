import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const uniswapFactory = ''

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()
  const { deploy } = deployments

  console.log(`Start deploying PredyPool with ${deployer}`)

  const AddPairLogic = await ethers.getContract('AddPairLogic', deployer)
  const ReallocationLogic = await ethers.getContract('ReallocationLogic', deployer)
  const LiquidationLogic = await ethers.getContract('LiquidationLogic', deployer)
  const ReaderLogic = await ethers.getContract('ReaderLogic', deployer)
  const SupplyLogic = await ethers.getContract('SupplyLogic', deployer)
  const TradeLogic = await ethers.getContract('TradeLogic', deployer)
  const MarginLogic = await ethers.getContract('MarginLogic', deployer)

  await deploy('PredyPool', {
    from: deployer,
    args: [],
    libraries: {
      ReallocationLogic: ReallocationLogic.address,
      LiquidationLogic: LiquidationLogic.address,
      ReaderLogic: ReaderLogic.address,
      AddPairLogic: AddPairLogic.address,
      SupplyLogic: SupplyLogic.address,
      TradeLogic: TradeLogic.address,
      MarginLogic: MarginLogic.address
    },
    log: true,
    proxy: {
      execute: {
        init: {
          methodName: 'initialize',
          args: [
            uniswapFactory
          ],
        },
      },
    },
  })
}

export default func
