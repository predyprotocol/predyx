import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { Filler } from '../addressList'

const SwapRouter02Address = '0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45'
const QuoterV2Address = '0x61fFE014bA17989E743c5F6cB21bF9697530B21e'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying settlements with ${deployer}`)

  const { deploy } = deployments

  const PredyPool = await ethers.getContract('PredyPool', deployer)

  await deploy('DirectSettlement', {
    from: deployer,
    log: true,
    args: [PredyPool.address, Filler]
  })

  await deploy('UniswapSettlement', {
    from: deployer,
    log: true,
    args: [PredyPool.address, SwapRouter02Address, QuoterV2Address, Filler]
  })

  await deploy('RevertSettlement', {
    from: deployer,
    log: true,
    args: [PredyPool.address]
  })
}

export default func
