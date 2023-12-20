import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { Filler, Permit2 } from '../addressList'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying gamma market with ${deployer}`)

  const { deploy } = deployments

  const PredyPool = await ethers.getContract('PredyPool', deployer)
  const PredyPoolQuoter = await ethers.getContract('PredyPoolQuoter', deployer)

  await deploy('PerpMarket', {
    from: deployer,
    log: true,
    args: [PredyPool.address, Permit2, Filler, PredyPoolQuoter.address]
  })

  const PerpMarket = await ethers.getContract('PerpMarket', deployer)

  await deploy('PerpMarketQuoter', {
    from: deployer,
    log: true,
    args: [PerpMarket.address]
  })
}

export default func
