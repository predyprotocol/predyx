import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const Permit2Address = ''

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying gamma market with ${deployer}`)

  const { deploy } = deployments

  const PredyPool = await ethers.getContract('PredyPool', deployer)

  await deploy('PerpDutchOrderValidator', {
    from: deployer,
    log: true,
  })

  await deploy('PerpLimitOrderValidator', {
    from: deployer,
    log: true,
  })

  await deploy('PerpMarket', {
    from: deployer,
    log: true,
    args: [PredyPool.address, Permit2Address]
  })
}

export default func
