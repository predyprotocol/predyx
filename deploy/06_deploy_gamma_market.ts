import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const Permit2Address = ''

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying predict market with ${deployer}`)

  const { deploy } = deployments

  const PredyPool = await ethers.getContract('PredyPool', deployer)

  await deploy('GammaDutchOrderValidator', {
    from: deployer,
    log: true,
  })

  await deploy('GammaLimitOrderValidator', {
    from: deployer,
    log: true,
  })

  await deploy('GammaTradeMarket', {
    from: deployer,
    log: true,
    args: [PredyPool.address, Permit2Address]
  })
}

export default func
