pragma solidity 0.6.12;

// import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../IAdaptor.sol";
import "../AdaptorRouter.sol";

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

  // function totalToken() external view returns (uint256);
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

  constructor(address router_, address saver_) public {
    router = router_;
    saver = saver_;
  }

  function getName() override view public returns (string memory) {
    return "AlpacaAdaptor";
  }

  /**
   *
   * getRate APR
   *
   */
  function getRate(address token_) 
    external override view 
    returns(uint256 apr) {
    apr = _calcRate(token_, 0);
  }

  /**
   *
   * _calcRate APR
   *
   */
  function _calcRate(address baseToken, uint256 _amount) 
    internal view
    returns (uint256 apr) {
      address alpacaAddr = AdaptorRouter(router).getPair(baseToken, getName());
      AlpacaValut _valut = AlpacaValut(alpacaAddr);
      IVaultConfig config = IVaultConfig(_valut.config());

      uint256 vaultDebtVal = _valut.vaultDebtVal();
      uint256 tokenAddressBalance = IERC20(baseToken).balanceOf(alpacaAddr);
      tokenAddressBalance = tokenAddressBalance.add(_amount);

      uint256 interestRate = config.getInterestRate(vaultDebtVal, tokenAddressBalance);
      uint256 reservePoolBps = config.getReservePoolBps();

      uint256 debRate = vaultDebtVal.mul(1e19).div(vaultDebtVal.add(tokenAddressBalance));

      uint256 totalPiece = 1e19;
      uint256 afterReservePoolRate = totalPiece.sub(reservePoolBps.mul(1e15));
      // apr = 	interestRate * yearsSecond * vaultDebtValRate * afterReservePoolRate / 1e36;
      apr = interestRate.mul(31536e3).mul(debRate).mul(afterReservePoolRate).div(1e36);
  }

  /**
   *  current price of cTokenLike token
   */
  function getPriceInToken(address baseToken)
    public override view
    returns (uint256) {
      address alpacaAddr = AdaptorRouter(router).getPair(baseToken, getName());
      AlpacaValut _valut = AlpacaValut(alpacaAddr);
      return _valut.totalToken().div(_valut.totalSupply());
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
    external override
    returns (uint256 _tokens)
    {
      address alpacaAddr = AdaptorRouter(router).getPair(token_, getName());
      uint256 _balance = IERC20(token_).balanceOf(address(this));
      if (_balance > 0) {
        AlpacaValut(alpacaAddr).deposit(_balance);
        _tokens = IERC20(alpacaAddr).balanceOf(address(this));
      }
  }

  /**
   *
   * witdraw from adaptor
   *
   */
  function withdraw(address token_, uint256 _amount)
    external override
    returns (uint256 _tokens) {
      address alpacaAddr = AdaptorRouter(router).getPair(token_, getName());
      uint256 _balance = IERC20(alpacaAddr).balanceOf(address(this));
      if (_balance > 0) {
        AlpacaValut(alpacaAddr).withdraw(_amount);
        IERC20 _underlying = IERC20(token_);
        _tokens = _underlying.balanceOf(address(this));
        _underlying.safeTransfer(msg.sender, _amount);
      }
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
}