import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { Filler, Permit2 } from '../addressList'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying gamma market with ${deployer}`)

  const { deploy } = deployments

  const PredyPool = await deployments.get('PredyPool')
  const PredyPoolQuoter = await deployments.get('PredyPoolQuoter')

  await deploy('PerpMarket', {
    from: deployer,
    log: true,
    args: [PredyPool.address, Permit2, Filler, PredyPoolQuoter.address]
  })

  const PerpMarket = await deployments.get('PerpMarket')

  await deploy('PerpMarketQuoter', {
    from: deployer,
    log: true,
    args: [PerpMarket.address]
  })
}

export default func
