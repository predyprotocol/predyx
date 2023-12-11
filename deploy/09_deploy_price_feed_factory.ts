import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying predict market with ${deployer}`)

  const { deploy } = deployments

  await deploy('PriceFeedFactory', {
    from: deployer,
    log: true,
    args: []
  })

  /*
  const PriceFeedFactory = await ethers.getContract('PriceFeedFactory', deployer)
  PriceFeedFactory.createPriceFeed('', '', '1000000000000')
  */

}

export default func
