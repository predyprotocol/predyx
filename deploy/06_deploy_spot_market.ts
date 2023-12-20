import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { Filler, Permit2 } from '../addressList'

const SwapRouter02Address = '0xE592427A0AEce92De3Edee1F18E0157C05861564'
const QuoterV2Address = '0x61fFE014bA17989E743c5F6cB21bF9697530B21e'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying predict market with ${deployer}`)

  const { deploy } = deployments

  await deploy('SpotMarket', {
    from: deployer,
    log: true,
    args: [Permit2]
  })

  await deploy('SpotMarketQuoter', {
    from: deployer,
    log: true,
    args: []
  })

  const SpotMarket = await ethers.getContract('SpotMarket', deployer)

  await deploy('UniswapSettlement', {
    from: deployer,
    log: true,
    args: [SpotMarket.address, SwapRouter02Address, QuoterV2Address, Filler]
  })
}

export const tags = ['spot']

export default func
