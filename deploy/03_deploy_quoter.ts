import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying settlements with ${deployer}`)

  const { deploy } = deployments

  const PredyPool = await deployments.get('PredyPool')
  const RevertSettlement = await deployments.get('RevertSettlement')

  await deploy('PredyPoolQuoter', {
    from: deployer,
    log: true,
    args: [PredyPool.address, RevertSettlement.address]
  })
}

func.tags = ['quoter'];

export default func
