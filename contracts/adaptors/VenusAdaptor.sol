/**
 * @title: VenusAdaptor
 */
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IAdaptor.sol";
import "../AdaptorRouter.sol";


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

interface VBNB {
  function mint() external payable;
}

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
  uint256 public secondsPerBlock;

  event Withdraw(address token_, uint256 amount, uint256 _bamount, uint256 tokenPrice);

  constructor(address router_, address saver_) public {
    router = router_;
    saver = saver_;
    secondsPerBlock = 3;
  }
  
  modifier onlySaver() {
    require(msg.sender == saver, "Ownable: caller is not Saver");
    _;
  }

  function getName() 
    public override view 
    returns (string memory) {
      return "VenusAdaptor";
  }

  /**
   * Calculate next supply rate for Venus, given an `_amount` supplied
   */
  function nextSupplyRate(address token_, uint256 _amount)
    external override view
    returns (uint256) {
      address cToken_ = AdaptorRouter(router).getPair(token_, getName());
      CERC20 cToken = CERC20(cToken_);
      WhitePaperInterestRateModel white = WhitePaperInterestRateModel(
        CERC20(cToken_).interestRateModel()
      );
      uint256 ratePerBlock = white.getSupplyRate(
        cToken.getCash().add(_amount),
        cToken.totalBorrows(),
        cToken.totalReserves(),
        cToken.reserveFactorMantissa()
      );
      return ratePerBlock.div(secondsPerBlock);
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
   * getRate 
   * interest rate per second, scaled by 1e18
   */
  function getRate(address token_)
    external override view
    returns (uint256) {
      address cToken_ = AdaptorRouter(router).getPair(token_, getName());
      return CERC20(cToken_).supplyRatePerBlock().div(secondsPerBlock);
  }

  /**
   *
   * deposit
   *
   */
  function deposit(address token_) 
    external override payable onlySaver
    returns (uint256 crTokens) {
      require(router != address(0), "router not found");
      AdaptorRouter config = AdaptorRouter(router);
      address cToken_ = config.getPair(token_, getName());
      require(cToken_ != address(0), "token_ target empty");
      uint256 balance = IERC20(token_).balanceOf(address(this));
      if (balance != 0) {
        // if current token is wBNB, convert wBNB to BNB
        if (token_ == config.getWrappedNativeAddr()) {
          IWETH(config.getWrappedNativeAddr()).withdraw(balance);
          VBNB(cToken_).mint{ value: balance }();
        } else {
          IERC20(token_).safeApprove(cToken_, balance);
          require(CERC20(cToken_).mint(balance) == 0, "Error minting crTokens");
        }
        crTokens = IERC20(cToken_).balanceOf(address(this));
      }
  }

  /**
   *
   * withdraw
   *
   */
  function withdraw(address token_, uint256 _bamount)
    external override onlySaver
    returns (uint256 tokens) {
      AdaptorRouter config = AdaptorRouter(router);
      address cToken_ = config.getPair(token_, getName());

      uint256 tokenPrice = getPriceInToken(token_);
      uint256 _amount = _bamount.mul(10**18).div(tokenPrice);

      require(CERC20(cToken_).redeem(_amount) == 0, "Error redeeming crTokens");

      // if current token is wBNB, convert BNB to wBNB
      if (token_ == config.getWrappedNativeAddr()) {
        IWETH(config.getWrappedNativeAddr()).deposit{ value: _bamount }();
      }

      IERC20 _underlying = IERC20(token_);
      tokens = _underlying.balanceOf(address(this));
      _underlying.safeTransfer(msg.sender, tokens);

      emit Withdraw(token_, _amount, _bamount, tokenPrice);
  } 

  /**
   *
   * Get the underlying balance on the lending protocol
   *
   */
  function availableLiquidity(address token_) 
    external override view 
    returns (uint256) {
      address cToken_ = AdaptorRouter(router).getPair(token_, getName());
      return CERC20(cToken_).getCash();
  }

  fallback() external payable{}
}