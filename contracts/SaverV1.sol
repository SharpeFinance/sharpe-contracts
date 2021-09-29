// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/ISaver.sol";
import "./adaptors/AlpacaAdaptor.sol";
import "./adaptors/VenusAdaptor.sol";

// This contract is owned by Timelock.
contract SaverV1 is ISaver, Ownable {

  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  uint256 constant SHARE_BASE = 1e18;
  uint256 constant RATE_BASE = 1e8;

  address[] public allAdaptors;
  // address[] public currentAdaptorsUsed;
  mapping(address => address[]) public getCurrentAdaptorsUsed;

  uint256 public minRateDifference = 100000000000000000; // 0.1% min

  event Rebalance(address who, address token_, address adaptor, uint256 amount);
  event Withdraw(address to, address token_, uint256 amount, uint256 balance);

  function setAdaptors(address[] memory allAdaptors_) external {
    allAdaptors = allAdaptors_;
  }

  /**
   *
   * getRate
   *
   * @param token_ : token address
   * @return : apr
   */
  function getRate(address token_) external override view returns(uint256) {
    uint256 totalRate = 0;
    address[] memory currentAdaptorsUsed = getCurrentAdaptorsUsed[token_];
    for (uint256 i = 0; i < currentAdaptorsUsed.length; i++) {
      uint256 adaptorRate = IAdaptor(currentAdaptorsUsed[i]).getRate(token_);
      totalRate = totalRate.add(adaptorRate);
    }
    return totalRate;
  }

  /**
   *
   * getAmount 
   *
   * @param token_ : token address
   * @return : amount in saver
   */
  function getAmount(address token_) 
    external override view returns(uint256) {
    return _getCurrentAllocations(token_);
  }

  /**
   *
   * deposit tokens through adaptor
   *
   * @param token_ : address of baseToken
   * @param _adaptorAddr : address of adaptor
   * @param _amount : amount
   * @return tokens : new tokens minted
   */
  function _depositAdaptorTokens(address token_, address _adaptorAddr, uint256 _amount) 
    internal 
    returns (uint256 tokens) {
      if (_amount == 0) {
        return tokens;
      }

      IAdaptor _adaptor = IAdaptor(_adaptorAddr);
      IERC20(token_).safeTransfer(_adaptorAddr, _amount);
      tokens = _adaptor.deposit(token_);
  }

  /**
   *
   * _withdrawFromAll
   *
   * @param adaptors : adaptor address list
   *
   */
  function _withdrawFromAll(address token_, address[] storage adaptors) 
    internal {
      for (uint8 i = 0; i < adaptors.length; i++) {
        address _adaptorAddr = adaptors[i];
        IAdaptor _adaptor = IAdaptor(_adaptorAddr);
        uint256 _withdrawAmount = _adaptor.getAmount(token_);
        if (_withdrawAmount > 0) {
          _adaptor.withdraw(token_, _withdrawAmount);
        }
      }
  }

  /**
   *
   * rebalance
   *
   * @param token_ : token address
   *
   */
  function rebalance(address token_) external override {
    uint256 _newAmount = _contractBalanceOf(token_);

    bool shouldRebalance;
    address bestAdaptor;

    address[] storage currentAdaptorsUsed = getCurrentAdaptorsUsed[token_];
    if (currentAdaptorsUsed.length == 1 && _newAmount > 0) {
      (shouldRebalance, bestAdaptor) = _rebalanceCheck(token_, _newAmount, currentAdaptorsUsed[0]);
      if (!shouldRebalance) {
        // deposit to currently used
        _depositAdaptorTokens(token_, currentAdaptorsUsed[0], _newAmount);
        return; // hasNotRebalanced
      }
    }

    if (currentAdaptorsUsed.length != 0) {
      // withdraw all before
      _withdrawFromAll(token_, currentAdaptorsUsed);
    }

    // remove all elements from `currentAdaptorsUsed`
    delete getCurrentAdaptorsUsed[token_];

    uint256 tokenBalance = _contractBalanceOf(token_);
    require(tokenBalance != 0, "No Balance");

    // (we are re-fetching aprs because after redeeming they changed)
    (shouldRebalance, bestAdaptor) = _rebalanceCheck(token_, tokenBalance, address(0));
    require(bestAdaptor != address(0), "No bestAdaptor");

    // deposit to bestAdaptor
    _depositAdaptorTokens(token_, bestAdaptor, tokenBalance);
    // update currentAdaptorsUsed in Saver storage
    currentAdaptorsUsed.push(bestAdaptor);

    emit Rebalance(msg.sender, token_, bestAdaptor, tokenBalance);
  }

  /**
   *
   * getAPRs 
   *
   * @param token_ : token address
   *
   */
  function getAPRs(address token_) public view
    returns (address[] memory addresses, uint256[] memory aprs) {
      address currAdaptor;
      addresses = new address[](allAdaptors.length);
      aprs = new uint256[](allAdaptors.length);
      for (uint8 i = 0; i < allAdaptors.length; i++) {
        currAdaptor = allAdaptors[i];
        addresses[i] = currAdaptor;
        aprs[i] = IAdaptor(currAdaptor).getRate(token_);
      }
  }

  /**
   * Check if a rebalance is needed
   *
   */
  function _rebalanceCheck(address token_, uint256 _amount, address currentAdaptor)
    internal view
    returns (bool, address) {

    (address[] memory addresses, uint256[] memory aprs) = getAPRs(token_);
    if (aprs.length == 0) {
      return (false, address(0));
    }

    // we are trying to find if the protocol with the highest APR can support all the liquidity
    // we intend to provide
    uint256 maxRate;
    address maxAddress;
    uint256 secondBestRate;
    address secondAddress;
    uint256 currApr;
    address currAddr;

    // find best rate and secondBestRate
    for (uint8 i = 0; i < aprs.length; i++) {
      currApr = aprs[i];
      currAddr = addresses[i];
      if (currApr > maxRate) {
        secondBestRate = maxRate;
        maxRate = currApr;
        maxAddress = currAddr;
      } else if (currApr <= maxRate && currApr >= secondBestRate) {
        secondBestRate = currApr;
        secondAddress = currAddr;
      }
    }

    if (currentAdaptor != address(0) && currentAdaptor != maxAddress) {
      return (true, maxAddress);
    } else {
      uint256 nextRate = _getAdaptorNextRate(token_, maxAddress, _amount);
      if (nextRate.add(minRateDifference) < secondBestRate) {
        return (true, maxAddress);
      }
    }

    return (false, maxAddress);
  }


  /**
   *
   * _getAdaptorNextRate
   *
   * @param _adaptorAddr : adaptor address
   * @param _amount : token amont
   *
   */
  function _getAdaptorNextRate(address token_, address _adaptorAddr, uint256 _amount)
    internal view
    returns (uint256 apr) {
      IAdaptor _adaptor = IAdaptor(_adaptorAddr);
      apr = _adaptor.nextSupplyRate(token_, _amount);
  }

  /**
   *
   * getCurrentAllocations
   *
   * @param token_ : token address
   *
   */
  function _getCurrentAllocations(address token_)
    internal view 
    returns (uint256 total) {
    address[] memory currentAdaptorsUsed = getCurrentAdaptorsUsed[token_];
    for (uint8 i = 0; i < currentAdaptorsUsed.length; i++) {
      address adaptorAddr = currentAdaptorsUsed[i];
      IAdaptor _adaptor = IAdaptor(adaptorAddr);
      total = total.add(_adaptor.getAmount(token_));
    }
  }

  /**
   *
   * contractBalanceOf
   *
   * @param _token : token address
   * @return : balance
   */
  function _contractBalanceOf(address _token) private view returns (uint256) {
    // Original implementation:
    //
    // return IERC20(_token).balanceOf(address(this));
    // Optimized implementation inspired by uniswap https://github.com/Uniswap/uniswap-v3-core/blob/main/contracts/UniswapV3Pool.sol#L144
    //
    // 0x70a08231 -> selector for 'function balanceOf(address) returns (uint256)'
    (bool success, bytes memory data) =
        _token.staticcall(abi.encodeWithSelector(0x70a08231, address(this)));
    require(success);
    return abi.decode(data, (uint256));
  }


  /**
   *
   * Withdraw from Saver
   *
   * @param token_ : token address
   * @param amount_ : amount
   * @param toAddress_ : to
   */
  function withdraw(address token_, uint256 amount_, address toAddress_) 
    external override {
    uint256 amountTo = amount_;
    address[] memory currentAdaptorsUsed = getCurrentAdaptorsUsed[token_];

    for (uint8 i = 0; i < currentAdaptorsUsed.length; i++) {
      address adaptorAddr = currentAdaptorsUsed[i];
      IAdaptor _adaptor = IAdaptor(adaptorAddr);
      uint256 allAmount = _adaptor.getAmount(token_);
      // same or greater
      if (allAmount >= amountTo) {
        _adaptor.withdraw(token_, amountTo);
        amountTo = amountTo.sub(allAmount);
      } else {
        _adaptor.withdraw(token_, amountTo);
      }
    }

    uint256 balance = IERC20(token_).balanceOf(address(this));
    if (balance > 0) {
      IERC20(token_).safeTransfer(toAddress_, amount_);
    } else {
      // native token?
      SafeToken.safeTransferETH(toAddress_, amount_);
    }

    emit Withdraw(toAddress_, token_, amount_, balance);
  }

  fallback() external payable{}
}