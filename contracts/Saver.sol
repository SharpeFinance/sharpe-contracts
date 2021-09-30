// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/ISaver.sol";
import "./interfaces/IRebalancer.sol";

import "./adaptors/AlpacaAdaptor.sol";
import "./adaptors/VenusAdaptor.sol";

// This contract is owned by Timelock.
contract Saver is ISaver, Ownable {

  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  uint256 constant SHARE_BASE = 1e18;
  uint256 constant RATE_BASE = 1e8;

  address[] public allAdaptors;

  // token => rebalncer
  mapping(address => address) public getTokenRebalancer;

  // token => allocations
  mapping(address => uint256[]) public getLastAllocations;

  event Rebalance(address who, address token_, address adaptor, uint256 amount);
  event Withdraw(address to, address token_, uint256 amount, uint256 balance);
  event Deposit(address who, address token_, uint256 amount, uint256 balance, address adaptor);
  event DoRebalance(bool lowLiquidity, uint256[] toMintAllocations, uint256 totalToMint);
  event DepositMultiple(address[] tokenAddresses, uint256[] adaptorAmounts);
  event RebalanceDeposit(address baseToken, address[] tokenAddresses, uint256[] amounts, uint256[] newAmounts);

  function setAdaptors(address[] memory allAdaptors_) external onlyOwner {
    allAdaptors = allAdaptors_;
  }

  function getAllAdaptors() external view returns (address[] memory) {
    return allAdaptors;
  }

  function setTokenRebalancer(address token_, address rebalancer) external onlyOwner {
    getTokenRebalancer[token_] = rebalancer;
  }

  function getCurrentAllocations(address token_) external view
    returns (address[] memory addresses, uint256[] memory amounts, uint256 total) {
      return _getCurrentAllocations(token_);
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
   *
   * getAmount 
   *
   * @param token_ : token address
   * @return : amount in saver
   */
  function getAmount(address token_) 
    external override view returns(uint256) {
      (address[] memory tokenAddresses, uint256[] memory amounts, uint256 totalInUnderlying) = _getCurrentAllocations(token_);
      return totalInUnderlying;
  }

  /**
   *
   * getRate
   *
   * @param token_ : token address
   * @return avgApr : avgApr
   */
  function getRate(address token_)
    public view override
    returns (uint256 avgApr) {
      (, uint256[] memory amounts, uint256 total) = _getCurrentAllocations(token_);
      uint256 currApr;
      uint256 weight;
      for (uint256 i = 0; i < allAdaptors.length; i++) {
        if (amounts[i] == 0) {
          continue;
        }
        currApr = IAdaptor(allAdaptors[i]).getRate(token_);
        weight = amounts[i].mul(10**18).div(total);
        avgApr = avgApr.add(currApr.mul(weight).div(10**18));
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
    _rebalance(token_, false);
  }

  function openRebalance(address token_, uint256[] calldata _newAllocations)
    external 
      returns (bool, uint256 avgApr) {
        uint256 initialAPR = getRate(token_);
        // Validate and update rebalancer allocations
        address reblancerAddr = getTokenRebalancer[token_];
        IRebalancer(reblancerAddr).setAllocations(_newAllocations, allAdaptors);
        bool hasRebalanced = _rebalance(token_, false);
        uint256 newAprAfterRebalance = getRate(token_);
        require(newAprAfterRebalance > initialAPR, "APR not improved");
        return (hasRebalanced, newAprAfterRebalance);
  }

  function _getCurrentAllocations(address token_) internal view 
    returns (address[] memory tokenAddresses, uint256[] memory amounts, uint256 total) {
      tokenAddresses = new address[](allAdaptors.length);
      amounts = new uint256[](allAdaptors.length);

      address currentAdaptorAddr;

      for (uint256 i = 0; i < allAdaptors.length; i++) {
        currentAdaptorAddr = allAdaptors[i];
        tokenAddresses[i] = currentAdaptorAddr;
        IAdaptor _adaptor = IAdaptor(currentAdaptorAddr);
        amounts[i] = _adaptor.getAmount(token_);
        total = total.add(amounts[i]);
      }

      return (tokenAddresses, amounts, total);
  }

  function _mintWithAmounts(address token_, address[] memory tokenAddresses, uint256[] memory adaptorAmounts) internal {
    require(tokenAddresses.length == adaptorAmounts.length, "All tokens length != allocations length");
    uint256 currAmount;
    emit DepositMultiple(tokenAddresses, adaptorAmounts);
    for(uint256 i = 0; i < adaptorAmounts.length; i++) {
      currAmount = adaptorAmounts[i];
      if (currAmount == 0) {
        continue;
      }
      _depositAdaptorTokens(token_, tokenAddresses[i], currAmount);
    }
  }

  function _depositAdaptorTokens(address token_, address _adaptorAddr, uint256 _amount) 
    internal 
    returns (uint256 tokens) {
      if (_amount == 0) {
        return tokens;
      }

      IAdaptor _adaptor = IAdaptor(_adaptorAddr);
      uint256 balance = _contractBalanceOf(token_);
      emit Deposit(msg.sender, token_, _amount, balance, _adaptorAddr);
      require(balance >= _amount, "balance not enought");
      IERC20(token_).safeTransfer(_adaptorAddr, _amount);
      tokens = _adaptor.deposit(token_);
  }

  function _redeemAllNeeded(
    address baseToken,
    address[] memory tokenAddresses,
    uint256[] memory amounts,
    uint256[] memory newAmounts
    ) internal returns (
      uint256[] memory toMintAllocations,
      uint256 totalToMint,
      bool lowLiquidity
    ) {
    require(amounts.length == newAmounts.length, 'Lengths not equal');
    toMintAllocations = new uint256[](amounts.length);
    IAdaptor adaptor;
    uint256 currAmount;
    uint256 newAmount;
    address adaptorAdr;
    emit RebalanceDeposit(baseToken, tokenAddresses, amounts, newAmounts);
    // check the difference between amounts and newAmounts
    for (uint256 i = 0; i < amounts.length; i++) {
      adaptorAdr = tokenAddresses[i];
      newAmount = newAmounts[i];
      currAmount = amounts[i];
      adaptor = IAdaptor(adaptorAdr);
      if (currAmount > newAmount) {
        toMintAllocations[i] = 0;
        uint256 toRedeem = currAmount.sub(newAmount);
        uint256 availableLiquidity = adaptor.availableLiquidity(baseToken);
        if (availableLiquidity < toRedeem) {
          lowLiquidity = true;
          toRedeem = availableLiquidity;
        }
        // redeem the difference
        _redeemProtocolTokens(
          adaptorAdr,
          baseToken,
          toRedeem
        );
      } else {
        toMintAllocations[i] = newAmount.sub(currAmount);
        totalToMint = totalToMint.add(toMintAllocations[i]);
      }
    }
  }

  function _redeemProtocolTokens(address _adaptorAddr, address _token, uint256 _amount)
    internal
    returns (uint256 tokens) {
      if (_amount == 0) {
        return tokens;
      }
      tokens = IAdaptor(_adaptorAddr).withdraw(_token, _amount);
  }

  function _checkIsSame(uint256[] memory array1, uint256[] memory array2) internal returns (bool) {
    bool isSame = array1.length  == array2.length;
    if (isSame) {
      for (uint256 i = 0; i < array1.length || !isSame; i++) {
        if (array1[i] != array2[i]) {
          isSame = false;
          break;
        }
      }
    }
    return isSame;
  }

  function _rebalance(address token_, bool _skipWholeRebalance) internal returns (bool) {
    // compare current allocations with Rebalancer's allocations
    uint256[] storage lastAllocations = getLastAllocations[token_];
    bool isInitial = lastAllocations.length == 0;
    require(getTokenRebalancer[token_] != address(0), "rebalancer not exist");

    uint256[] memory rebalancerLastAllocations = IRebalancer(getTokenRebalancer[token_]).getAllocations();
    bool areAllocationsEqual = _checkIsSame(lastAllocations, rebalancerLastAllocations);
    
    uint256 balance = _contractBalanceOf(token_);
    if (areAllocationsEqual && balance == 0) {
      return false;
    }

    if (balance > 0) {
      // first time rebalance
      if (lastAllocations.length == 0 && _skipWholeRebalance) {
        // save
        getLastAllocations[token_] = rebalancerLastAllocations;
      }
      _mintWithAmounts(token_, allAdaptors, _amountsFromAllocations(rebalancerLastAllocations, balance));
    }

    if (_skipWholeRebalance || areAllocationsEqual) {
      return false;
    }

    (address[] memory tokenAddresses, uint256[] memory amounts, uint256 totalInUnderlying) = _getCurrentAllocations(token_);
    uint256[] memory newAmounts = _amountsFromAllocations(rebalancerLastAllocations, totalInUnderlying);
    (uint256[] memory toMintAllocations, uint256 totalToMint, bool lowLiquidity) = _redeemAllNeeded(token_, tokenAddresses, amounts, newAmounts);
    emit DoRebalance(lowLiquidity, toMintAllocations, totalToMint);
    _doRebalance(token_, lowLiquidity, toMintAllocations, totalToMint, rebalancerLastAllocations);
    return true; // hasRebalanced
  }

  function _doRebalance(address token_, bool lowLiquidity, uint256[] memory toMintAllocations, uint256 totalToMint, uint256[] memory rebalancerLastAllocations) internal {
    // liquidity do not update
    if (!lowLiquidity) {
      // Update lastAllocations with rebalancerLastAllocations
      delete getLastAllocations[token_];
      getLastAllocations[token_] = rebalancerLastAllocations;
    }

    uint256 totalRedeemd = _contractBalanceOf(token_);
    if (totalRedeemd > 1 && totalToMint > 1) {
      // Do not mint directly using toMintAllocations check with totalRedeemd
      uint256[] memory tempAllocations = new uint256[](toMintAllocations.length);
      for (uint256 i = 0; i < toMintAllocations.length; i++) {
        // Calc what would have been the correct allocations percentage if all was available
        tempAllocations[i] = toMintAllocations[i].mul(100000).div(totalToMint);
      }
      uint256[] memory partialAmounts = _amountsFromAllocations(tempAllocations, totalRedeemd);
      _mintWithAmounts(token_, allAdaptors, partialAmounts);
    }
  }

  /**
   * Calculate amounts from percentage allocations (100000 => 100%)
   *
   * @param allocations : array of protocol allocations in percentage
   * @param total : total amount
   * @return : array with amounts
   */
  function _amountsFromAllocations(uint256[] memory allocations, uint256 total)
    internal pure returns (uint256[] memory) {
    uint256[] memory newAmounts = new uint256[](allocations.length);
    uint256 currBalance = 0;
    uint256 allocatedBalance = 0;

    for (uint256 i = 0; i < allocations.length; i++) {
      if (i == allocations.length - 1) {
        newAmounts[i] = total.sub(allocatedBalance);
      } else {
        currBalance = total.mul(allocations[i]).div(100000);
        allocatedBalance = allocatedBalance.add(currBalance);
        newAmounts[i] = currBalance;
      }
    }
    return newAmounts;
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
    for (uint8 i = 0; i < allAdaptors.length; i++) {
      address adaptorAddr = allAdaptors[i];
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
      if (address(this).balance > 0) {
        // native token?
        SafeToken.safeTransferETH(toAddress_, amount_);
      }
    }
    emit Withdraw(toAddress_, token_, amount_, balance);
  }

  fallback() external payable{}
}