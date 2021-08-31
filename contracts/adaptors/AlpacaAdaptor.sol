/**
 * @title: AlpacaAdaptor
 */
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IAdaptor.sol";
import "../AdaptorRouter.sol";
import "../SafeToken.sol";


interface AlpacaValut {
  /// @dev Return the total ERC20 entitled to the token holders. Be careful of unaccrued interests.
  function totalToken() external view returns (uint256);

  /// @dev Add more ERC20 to the bank. Hope to get some good returns.
  function deposit(uint256 amountToken) external payable;

  /// @dev Withdraw ERC20 from the bank by burning the share tokens.
  function withdraw(uint256 share) external;

  /// @dev Request funds from user through Vault
  function requestFunds(address targetedToken, uint amount) external;

  function token() external view returns (address);

  function config() external view returns (address);
  function vaultDebtVal() external view returns (uint256);
  function reservePool() external view returns (uint256);

  function totalSupply() external view returns (uint256);
}

interface IVaultConfig {
  function getReservePoolBps() external view returns (uint256);
  function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256);
}

contract AlpacaAdaptor is IAdaptor {

  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  
  address public router;
  address public saver;

  event Withdraw(address token_, uint256 input, uint256 price, uint256 amount, uint256 output);

  constructor(address router_, address saver_) public {
    router = router_;
    saver = saver_;
  }

  modifier onlySaver() {
    require(msg.sender == saver, "Ownable: caller is not Saver");
    _;
  }

  function getName() 
    override view public 
    returns (string memory) {
      return "AlpacaAdaptor";
  }

  /**
   * getRate
   * interest rate per second, scaled by 1e18
   */
  function getRate(address token_) 
    external override view 
    returns(uint256 apr) {
    apr = _calcRate(token_, 0);
  }

  /**
   *
   * _calcRate
   *
   */
  function _calcRate(address baseToken, uint256 _amount) 
    internal view
    returns (uint256 rate) {
      require(baseToken != address(0), "baseToken must provide");

      address alpacaAddr = AdaptorRouter(router).getPair(baseToken, getName());
      AlpacaValut _valut = AlpacaValut(alpacaAddr);

      address configAddr = _valut.config();
      require(configAddr != address(0), "config address not found");

      IVaultConfig config = IVaultConfig(configAddr);

      uint256 BASE_19 = 10**19;
      uint256 BASE_15 = 10**15;
      uint256 BASE_37 = 10**37;

      uint256 vaultDebtVal = _valut.vaultDebtVal();
      uint256 tokenAddressBalance = IERC20(baseToken).balanceOf(alpacaAddr);
      tokenAddressBalance = tokenAddressBalance.add(_amount);

      uint256 reservePoolBps = config.getReservePoolBps();

      uint256 interestRate = config.getInterestRate(vaultDebtVal, tokenAddressBalance);
      uint256 depUtilizationRate = _getUtilizationRate(vaultDebtVal, tokenAddressBalance);
      uint256 afterReservePoolRate = BASE_19.sub(reservePoolBps.mul(BASE_15));

      rate = interestRate.mul(depUtilizationRate).mul(afterReservePoolRate).div(BASE_37);
  }

  function _getUtilizationRate(uint256 debtVal, uint256 balance)
    internal view 
    returns (uint256 rate) {
      rate = debtVal.mul(10**18).div(debtVal.add(balance));
  }

  /**
   *  current price of cTokenLike token
   */
  function getPriceInToken(address baseToken)
    public override view
    returns (uint256 price) {
      address alpacaAddr = AdaptorRouter(router).getPair(baseToken, getName());
      AlpacaValut _valut = AlpacaValut(alpacaAddr);
      price = _valut.totalToken().mul(10**18).div(_valut.totalSupply());
  }


  /**
   *  getStatus of Adaptor
   */
  function getStatus(address token_) 
    public view
    returns (uint256[] memory status) {
      address alpacaAddr = AdaptorRouter(router).getPair(token_, getName());
      AlpacaValut _valut = AlpacaValut(alpacaAddr);
      status = new uint256[](5);
      status[0] = _valut.totalToken();
      status[1] = _valut.totalSupply();
      status[2] = IERC20(alpacaAddr).balanceOf(address(this));
      status[3] = _calcRate(token_, 0);
      status[4] = IVaultConfig(_valut.config()).getReservePoolBps();
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
      amount = holdAmount.mul(tokenPrice).div(10**18);
  }
  
  /**
   *
   * nextSupplyRate
   *
   */
  function nextSupplyRate(address baseToken, uint256 _amount)
    external override view
    returns (uint256 lendAPR) {
      lendAPR = _calcRate(baseToken, _amount);
  }

  /**
   *
   * Deposit token
   *
   */
  function deposit(address token_)
    external override payable onlySaver
    returns (uint256 _tokens) {
      address alpacaAddr = AdaptorRouter(router).getPair(token_, getName());
      uint256 _balance = IERC20(token_).balanceOf(address(this));
      if (_balance > 0) {
        IERC20(token_).safeApprove(alpacaAddr, _balance);
        AlpacaValut(alpacaAddr).deposit(_balance);
        _tokens = IERC20(alpacaAddr).balanceOf(address(this));
      }
  }

  /**
   *
   * witdraw from adaptor
   *
   */
  function withdraw(address token_, uint256 _bamount)
    external override onlySaver
    returns (uint256 _tokens) {

      AdaptorRouter config = AdaptorRouter(router);
      address alpacaAddr = config.getPair(token_, getName());
      uint256 tokenPrice = getPriceInToken(token_);
      uint256 _amount = _bamount.mul(10**18).div(tokenPrice);

      uint256 _balance = IERC20(alpacaAddr).balanceOf(address(this));
      if (_balance > 0) {

        AlpacaValut(alpacaAddr).withdraw(_amount);

        // if current token is wBNB, convert BNB to wBNB
        if (token_ == config.getWrappedNativeAddr()) {
          IWETH(config.getWrappedNativeAddr()).deposit{ value: _bamount }();
        }

        IERC20 _underlying = IERC20(token_);
        _tokens = _underlying.balanceOf(address(this));

        if (_tokens > 0) {
          _underlying.safeTransfer(msg.sender, _tokens);
        } else {
          // native token?
          SafeToken.safeTransferETH(msg.sender, _bamount);
        }
      }

      emit Withdraw(token_, _bamount, tokenPrice, _amount, _tokens);
  }

  /**
   *
   * cash in adaptor
   *
   */
  function availableLiquidity(address token_)
    external override view 
    returns (uint256) {
      address alpacaAddr = AdaptorRouter(router).getPair(token_, getName());
      AlpacaValut _valut = AlpacaValut(alpacaAddr);
      uint256 reservePool = _valut.reservePool();
      uint256 tokenAddressBalance = IERC20(token_).balanceOf(alpacaAddr);
      return tokenAddressBalance.sub(reservePool);
  }

  fallback() external payable{}
}