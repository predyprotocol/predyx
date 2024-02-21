import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { Permit2 } from '../addressList'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying spot market with ${deployer}`)

  const { deploy } = deployments

  const SpotDutchOrderValidator = await deployments.get('SpotDutchOrderValidator')
  const SpotLimitOrderValidator = await deployments.get('SpotLimitOrderValidator')

  await deploy('SpotMarket', {
    from: deployer,
    log: true,
    args: [Permit2, SpotDutchOrderValidator.address, SpotLimitOrderValidator.address]
  })

  const SpotMarket = await deployments.get('SpotMarket')

  await deploy('SpotMarketQuoter', {
    from: deployer,
    log: true,
    args: [SpotMarket.address]
  })
}

func.tags = ['spot']

export default func
