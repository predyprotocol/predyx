import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { Filler, Permit2 } from '../addressList'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying predict market with ${deployer}`)

  const { deploy } = deployments

  const PredyPool = await ethers.getContract('PredyPool', deployer)
  const PredyPoolQuoter = await ethers.getContract('PredyPoolQuoter', deployer)

  await deploy('PredictMarket', {
    from: deployer,
    log: true,
    args: [PredyPool.address, Permit2, Filler, PredyPoolQuoter.address]
  })

  const PredictMarket = await ethers.getContract('PredictMarket', deployer)

  await deploy('PredictMarketQuoter', {
    from: deployer,
    log: true,
    args: [PredictMarket.address]
  })
}

export default func
