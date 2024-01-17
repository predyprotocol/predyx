import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { Filler, Permit2 } from '../addressList'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying predict market with ${deployer}`)

  const { deploy } = deployments

  const PredyPool = await deployments.get('PredyPool')
  const PredyPoolQuoter = await deployments.get('PredyPoolQuoter')

  await deploy('PredictMarket', {
    from: deployer,
    log: true,
    args: [],
    proxy: {
      execute: {
        init: {
          methodName: 'initialize',
          args: [PredyPool.address, Permit2, Filler, PredyPoolQuoter.address],
        },
      },
      proxyContract: "EIP173Proxy",
    },
  })

  const PredictMarket = await deployments.get('PredictMarket')

  await deploy('PredictMarketQuoter', {
    from: deployer,
    log: true,
    args: [PredictMarket.address]
  })
}

export default func
