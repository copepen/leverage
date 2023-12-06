import {loadFixture} from "@nomicfoundation/hardhat-toolbox/network-helpers"
import {expect} from "chai"
import {ethers} from "hardhat"
import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers"

const EURO3 = "0xa0e4c84693266a9d3bbef2f394b33712c76599ab"
const WMATIC = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"
const WETH = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619"
const DAI = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063"
const USDC = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"
const EURO3_WHALE_ADDR = "0xC24BaDF40e4687ea6a318FA86e4dEa8d7C307626" // 30000
const DAI_WHALE_ADDR = "0x18dA62bA13Ae20007fd42961Fd52f3128B54E678" // 6M
const PRICE_DECIMAL_PRECISION = 1e8
const ISSUANCE_FEE_DECIMAL_PRECISON = 1e6

const collaterals = [
  // DAI
  {
    token: "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063",
    priceFeed: "0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D",
    mcr: 110,
    mlr: 105,
    issuanceFee: 100,
    decimals: 18,
    isActive: true,
  },
  // MATIC
  {
    token: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
    priceFeed: "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0",
    mcr: 120,
    mlr: 110,
    issuanceFee: 100,
    decimals: 18,
    isActive: true,
  },
]

describe("VaultLeverageZapper", function () {
  let owner: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress

  let daiWhale: SignerWithAddress
  let euro3Whale: SignerWithAddress

  let dai: any
  let weth: any
  let wmatic: any
  let euro3: any

  async function deployAndSetupConfig() {
    const [owner, user1, user2, euro3Treasury, borrowFeeRecipient] = await ethers.getSigners()
    dai = await ethers.getContractAt("IERC20", DAI)
    weth = await ethers.getContractAt("IERC20", WETH)
    wmatic = await ethers.getContractAt("IERC20", WMATIC)
    euro3 = await ethers.getContractAt("IERC20", EURO3)

    daiWhale = await ethers.getImpersonatedSigner(DAI_WHALE_ADDR)
    await dai.connect(daiWhale).transfer(user1.address, ethers.parseEther("10000"))
    await dai.connect(daiWhale).transfer(user2.address, ethers.parseEther("10000"))

    euro3Whale = await ethers.getImpersonatedSigner(EURO3_WHALE_ADDR)
    await euro3.connect(euro3Whale).transfer(euro3Treasury.address, ethers.parseEther("5000"))

    // 1. deploy contracts
    // 1.1 deploy VaultManager contract
    const VaultManager = await ethers.getContractFactory("VaultManager")
    const vaultManager = await VaultManager.deploy(EURO3, euro3Treasury.address)
    const vaultManagerAddr = vaultManager.target

    // 1.2 deploy VaultLeverageZapper contract
    const VaultLeverageZapper = await ethers.getContractFactory("VaultLeverageZapper")
    const vaultLeverageZapper = await VaultLeverageZapper.deploy(vaultManagerAddr)
    const vaultLeverageZapperAddr = vaultLeverageZapper.target

    // 1.3 deploy VaultLeverageZapper contract
    const Config = await ethers.getContractFactory("Config")
    const config = await Config.deploy()
    const configAddr = config.target

    // 1.4 deploy TokenSwapper contract
    const TokenSwapper = await ethers.getContractFactory("TokenSwapper")
    const tokenSwapper = await TokenSwapper.deploy()

    // 2. config contracts
    // 2.1 config VaultLeverageZapper contract
    await vaultLeverageZapper.setTokenSwapper(tokenSwapper.target)

    // 2.2 config VaultManager contract
    await vaultManager.setConfig(configAddr)
    await vaultManager.setVaultLeverageZapper(vaultLeverageZapperAddr)
    await euro3.connect(euro3Treasury).approve(vaultManagerAddr, ethers.parseEther("10000"))

    // 2.3 config Config contract
    await config.setBorrowFeeRecipient(borrowFeeRecipient.address)

    for (let index = 0; index < collaterals.length; index++) {
      await config.addCollateral(
        collaterals[index].token,
        collaterals[index].priceFeed,
        collaterals[index].mcr,
        collaterals[index].mlr,
        collaterals[index].issuanceFee,
        collaterals[index].decimals,
        collaterals[index].isActive
      )
    }

    // 2.4 config TokenSwapper contract
    await tokenSwapper.addUniswapV3Pool(DAI, USDC, 100)
    await tokenSwapper.addUniswapV3Pool(EURO3, USDC, 500)
    await tokenSwapper.addUniswapV3Pool(WMATIC, USDC, 500)

    return {vaultManager, vaultLeverageZapper, tokenSwapper, config, user1, user2, borrowFeeRecipient, euro3Treasury}
  }

  describe("deposit", function () {
    it("should deposit DAI", async function () {
      const {vaultLeverageZapper, vaultManager, tokenSwapper, config, user1, user2, borrowFeeRecipient, euro3Treasury} =
        await loadFixture(deployAndSetupConfig)

      const depositAmount = ethers.parseEther("10")

      // before deposit
      const user1DaiBalBefore: bigint = await dai.balanceOf(user1.address)
      const user1Euro3BalBefore: bigint = await euro3.balanceOf(user1.address)
      const feeRecipientEuro3BalBefore: bigint = await euro3.balanceOf(borrowFeeRecipient.address)

      // get swapPath
      const swapAmount = ethers.parseEther("100")
      const res = await tokenSwapper.calculateBestRoute.staticCall(EURO3, DAI, swapAmount)
      const swapPath = res.path.map((row) => {
        return {
          from: row[0],
          to: row[1],
        }
      })
      // call deposit
      await dai.connect(user1).approve(vaultLeverageZapper.target, depositAmount)
      await vaultLeverageZapper.connect(user1).deposit(DAI, depositAmount, true, swapPath)
      const daiPrice: bigint = await config.tokenPrice(DAI)
      const daiInfo = await config.getCollateralInfo(DAI)
      const mcr: bigint = daiInfo.mcr
      const issuanceFee: bigint = daiInfo.issuanceFee

      // after deposit
      const user1DaiBalAfter: bigint = await dai.balanceOf(user1.address)
      const user1Euro3BalAfter: bigint = await euro3.balanceOf(user1.address)
      const feeRecipientEuro3BalAfter: bigint = await euro3.balanceOf(borrowFeeRecipient.address)

      // real and expected amount calculation
      const daiOut: bigint = user1DaiBalBefore - user1DaiBalAfter
      const realEuro3InToUser1 = user1Euro3BalAfter - user1Euro3BalBefore
      const realEuro3InToRecipient = feeRecipientEuro3BalAfter - feeRecipientEuro3BalBefore
      const expectedEuro3Convert = (daiOut * daiPrice * BigInt(100)) / mcr / BigInt(PRICE_DECIMAL_PRECISION)
      const expectedEuro3InToRecipient = (expectedEuro3Convert * issuanceFee) / BigInt(ISSUANCE_FEE_DECIMAL_PRECISON)
      const expectedEuro3InToUser1 = expectedEuro3Convert - expectedEuro3InToRecipient

      // read onchain data from vault
      const daiVaultAddr = await vaultManager.vaultsByOwner(user1.address, 0)
      const daiVault = await ethers.getContractAt("IVault", daiVaultAddr)
      const vaultCollateral = await daiVault.totalCollateral()
      const vaultDebt = await daiVault.debtAmount()

      console.log("=== DAI leverage result ===")
      console.log("DAI price: ", daiPrice)
      console.log("DAI mcr: ", mcr)
      console.log("DAI issuanceFee: ", issuanceFee)

      console.log("==========================")
      console.log("Created DAI vault: ", daiVaultAddr)
      console.log("User1 DAI out: ", ethers.formatEther(daiOut))
      console.log("DAI vault collateral: ", ethers.formatEther(vaultCollateral))
      console.log("DAI vault debt: ", ethers.formatEther(vaultDebt))

      expect(vaultCollateral).to.greaterThan(daiOut)
      expect(expectedEuro3InToUser1).to.equal(vaultDebt)
    })
  })

  describe("depositETH", function () {
    it("should deposit MATIC", async function () {
      const {vaultLeverageZapper, vaultManager, tokenSwapper, config, user1, user2, borrowFeeRecipient, euro3Treasury} =
        await loadFixture(deployAndSetupConfig)

      const depositAmount = ethers.parseEther("10")

      // before deposit
      const user2CollBalBefore: bigint = await ethers.provider.getBalance(user2.address)

      // get swapPath
      const swapAmount = ethers.parseEther("100")
      const res = await tokenSwapper.calculateBestRoute.staticCall(EURO3, WMATIC, swapAmount)
      const swapPath = res.path.map((row) => {
        return {
          from: row[0],
          to: row[1],
        }
      })
      // call deposit
      await vaultLeverageZapper.connect(user2).depositETH(true, swapPath, {value: depositAmount})
      const collTokenPrice: bigint = await config.tokenPrice(WMATIC)
      const collTokenInfo = await config.getCollateralInfo(WMATIC)
      const mcr: bigint = collTokenInfo.mcr
      const issuanceFee: bigint = collTokenInfo.issuanceFee

      // after deposit
      const user2CollBalAfter: bigint = await ethers.provider.getBalance(user2.address)

      // real and expected amount calculation
      const collTokenOut: bigint = user2CollBalBefore - user2CollBalAfter
      const expectedEuro3Convert = (collTokenOut * collTokenPrice * BigInt(100)) / mcr / BigInt(PRICE_DECIMAL_PRECISION)
      const expectedEuro3InToRecipient = (expectedEuro3Convert * issuanceFee) / BigInt(ISSUANCE_FEE_DECIMAL_PRECISON)
      const expectedEuro3InToUser2 = expectedEuro3Convert - expectedEuro3InToRecipient

      // read onchain data from vault
      const maticVaultAddr = await vaultManager.vaultsByOwner(user2.address, 0)
      const maticVault = await ethers.getContractAt("IVault", maticVaultAddr)
      const vaultCollateral = await maticVault.totalCollateral()
      const vaultDebt = await maticVault.debtAmount()

      console.log("=== MATIC leverage result ===")
      console.log("MATIC price: ", collTokenPrice)
      console.log("MATIC mcr: ", mcr)
      console.log("MATIC issuanceFee: ", issuanceFee)

      console.log("==========================")
      console.log("Created MATIC vault: ", maticVaultAddr)
      console.log("User2 MATIC out: ", ethers.formatEther(collTokenOut))
      console.log("MATIC vault collateral: ", ethers.formatEther(vaultCollateral))
      console.log("MATIC vault debt: ", ethers.formatEther(vaultDebt))

      expect(vaultCollateral).to.greaterThan(collTokenOut)
      expect(expectedEuro3InToUser2).to.approximately(vaultDebt, vaultDebt / BigInt(100))
    })
  })
})
