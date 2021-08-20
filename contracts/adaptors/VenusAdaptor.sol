/**
 * @title: Venus adapter
 * @summary: Used for interacting with Venue. Has
 *           a common interface with all other protocol wrappers.
 *           This contract holds assets only during a tx, after tx it should be empty
 */
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../IAdaptor.sol";
import "../AdaptorRouter.sol";

// interface ILendingProtocol {
//   function mint() external returns (uint256);
//   function redeem(address account) external returns (uint256);
//   function nextSupplyRate(uint256 amount) external view returns (uint256);
//   function getAPR() external view returns (uint256);
//   function getPriceInToken() external view returns (uint256);
//   function token() external view returns (address);
//   function underlying() external view returns (address);
//   function availableLiquidity() external view returns (uint256);
// }

interface CERC20 {
  function mint(uint256 mintAmount) external returns (uint256);
  function comptroller() external view returns (address);
  function redeem(uint256 redeemTokens) external returns (uint256);
  function exchangeRateStored() external view returns (uint256);
  function supplyRatePerBlock() external view returns (uint256);

  function borrowRatePerBlock() external view returns (uint256);
  function totalReserves() external view returns (uint256);
  function getCash() external view returns (uint256);
  function totalBorrows() external view returns (uint256);
  function reserveFactorMantissa() external view returns (uint256);
  function interestRateModel() external view returns (address);

  function underlying() external view returns (address);
}

// import "../interfaces/WhitePaperInterestRateModel.sol";
interface WhitePaperInterestRateModel {
  function getBorrowRate(uint256 cash, uint256 borrows, uint256 _reserves) external view returns (uint256, uint256);
  function getSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactorMantissa) external view returns (uint256);
  function multiplier() external view returns (uint256);
  function baseRate() external view returns (uint256);
  function blocksPerYear() external view returns (uint256);
  function dsrPerBlock() external view returns (uint256);
}

contract VenusAdaptor is IAdaptor {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  address public router;
  address public saver;
  uint256 public blocksPerYear;

  constructor(address router_, address saver_) public {
    router = router_;
    saver = saver_;
    blocksPerYear = 10512000;
  }
  
  modifier onlySaver() {
    require(msg.sender == saver, "Ownable: caller is not Saver");
    _;
  }

  function getName() public override view returns (string memory) {
    return "VenusAdaptor";
  }

  /**
   * Calculate next supply rate for Compound, given an `_amount` supplied
   *
   * @param token_ : token address (eg DAI)
   * @param _amount : new underlying amount supplied (eg DAI)
   * @return : yearly net rate
   */
  function nextSupplyRate(address token_, uint256 _amount)
    external override view
    returns (uint256) {
      address cToken_ = AdaptorRouter(router).getPair(token_, getName());
      CERC20 cToken = CERC20(cToken_);
      WhitePaperInterestRateModel white = WhitePaperInterestRateModel(CERC20(cToken_).interestRateModel());
      uint256 ratePerBlock = white.getSupplyRate(
        cToken.getCash().add(_amount),
        cToken.totalBorrows(),
        cToken.totalReserves(),
        cToken.reserveFactorMantissa()
      );
      return ratePerBlock.mul(blocksPerYear).mul(100);
  }

  /**
   * @return current price of cTokenLike token
   */
  function getPriceInToken(address token_)
    public override view
    returns (uint256) {
      require(router != address(0), "router not found");
      address cToken_ = AdaptorRouter(router).getPair(token_, getName());
      require(cToken_ != address(0), "token_ target empty");
      return CERC20(cToken_).exchangeRateStored();
  }

  
  /** 
   *  get Amount
   */
  function getAmount(address baseToken) 
    external override view 
    returns (uint256 amount) {
      address alpacaAddr = AdaptorRouter(router).getPair(baseToken, getName());
      uint256 tokenPrice = getPriceInToken(baseToken);
      uint256 holdAmount = IERC20(alpacaAddr).balanceOf(address(this));
      amount = tokenPrice.mul(holdAmount).div(10**18);
  }

  /**
   * @return apr : current yearly net rate
   */
  function getRate(address token_)
    external override view
    returns (uint256) {
      // return nextSupplyRate(0);
      // more efficient
      address cToken_ = AdaptorRouter(router).getPair(token_, getName());
      return CERC20(cToken_).supplyRatePerBlock().mul(blocksPerYear).mul(100);
  }

  /**
   * Gets all underlying tokens in this contract and mints cTokenLike Tokens
   * tokens are then transferred to msg.sender
   * NOTE: underlying tokens needs to be sent here before calling this
   *
   */
  function deposit(address token_) 
    external override
    returns (uint256 crTokens) {
      address cToken_ = AdaptorRouter(router).getPair(token_, getName());
      uint256 balance = IERC20(token_).balanceOf(address(this));
      if (balance != 0) {
        IERC20 _token = IERC20(cToken_);
        require(CERC20(cToken_).mint(balance) == 0, "Error minting crTokens");
        crTokens = _token.balanceOf(address(this));
        // _token.safeTransfer(msg.sender, crTokens);
      }
  }

  /**
   * Gets all cTokenLike in this contract and redeems underlying tokens.
   * underlying tokens are then transferred to `_account`
   * NOTE: cTokenLike needs to be sent here before calling this
   *
   */
  function withdraw(address token_, uint256 _amount)
    external override
    returns (uint256 tokens) {
      address cToken_ = AdaptorRouter(router).getPair(token_, getName());
      require(CERC20(cToken_).redeem(_amount) == 0, "Error redeeming crTokens");
      IERC20 _underlying = IERC20(token_);
      tokens = _underlying.balanceOf(address(this));
      _underlying.safeTransfer(msg.sender, tokens);
  }

  /**
   * Get the underlying balance on the lending protocol
   *
   */
  function availableLiquidity(address token_) 
    external override view 
    returns (uint256) {
      address cToken_ = AdaptorRouter(router).getPair(token_, getName());
      return CERC20(cToken_).getCash();
  }
}
