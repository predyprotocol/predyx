import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const Permit2Address = ''

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying predict market with ${deployer}`)

  const { deploy } = deployments

  await deploy('SpotDutchOrderValidator', {
    from: deployer,
    log: true,
  })

  await deploy('SpotExclusiveLimitOrderValidator', {
    from: deployer,
    log: true,
  })

  await deploy('SpotMarket', {
    from: deployer,
    log: true,
    args: [Permit2Address]
  })
}

export default func
