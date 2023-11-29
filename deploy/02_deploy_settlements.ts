import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const SwapRouterAddress = ''
const FillerAddress = ''

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying settlements with ${deployer}`)

  const { deploy } = deployments

  const PredyPool = await ethers.getContract('PredyPool', deployer)

  await deploy('DirectSettlement', {
    from: deployer,
    log: true,
    args: [PredyPool.address, FillerAddress]
  })

  await deploy('UniswapSettlement', {
    from: deployer,
    log: true,
    args: [PredyPool.address, SwapRouterAddress]
  })

  await deploy('RevertSettlement', {
    from: deployer,
    log: true,
    args: [PredyPool.address]
  })
}

export default func
