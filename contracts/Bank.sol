// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/IInterestModel.sol";
import "./interfaces/IRegistry.sol";
import "./interfaces/ISaver.sol";

// This contract is owned by Timelock.
contract Bank is Ownable {

  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  uint256 constant SHARE_BASE = 1e18;
  uint256 constant UNIT_BASE = 1e18;
  uint256 constant RATE_BASE = 1e8;

  IRegistry public registry;

  struct PoolInfo {
    uint256 cashPerShare;
    uint256 loanPerShare;
    uint256 loanPerUnit;
    uint256 shares;
    uint256 units;
    uint256 lastTime;
  }

  // token => PoolInfo
  mapping(address => PoolInfo) public poolMap;

  struct UserInfo {
    uint256 shares;
    uint256 loanUnits;
  }

  // who => token => UserInfo
  mapping(address => mapping(address => UserInfo)) public userMap;

  constructor (IRegistry registry_) public {
    registry = registry_;
  }

  event Deposit(address who, uint256 cashAmount, uint256 sharesToAdd);

  function getInterestRate(
      address token_,
      uint256 cashPerShare_,
      uint256 loanPerShare_
  ) public view returns(uint256) {
    uint256 saverRate = ISaver(registry.saver()).getRate(token_);
    return IInterestModel(registry.interestModel()).getInterestRate(saverRate, cashPerShare_, loanPerShare_);
  }

  function updatePool(address token_) public {
    PoolInfo storage poolInfo = poolMap[token_];
    if (poolInfo.lastTime > 0) {
      uint256 interestRate = getInterestRate(token_, poolInfo.cashPerShare, poolInfo.loanPerShare);
      uint256 duration = now.sub(poolInfo.lastTime);

      // Updates loanPerShare.
      poolInfo.loanPerShare = poolInfo.loanPerShare.add(
          poolInfo.loanPerShare.mul(interestRate.mul(duration)).div(RATE_BASE));

      // Updates loanPerUnit.
      poolInfo.loanPerUnit = poolInfo.loanPerUnit.add(
          poolInfo.loanPerUnit.mul(interestRate.mul(duration)).div(RATE_BASE));

      // Updates cashPerShare.
      uint256 cashAmount = ISaver(registry.saver()).getAmount(token_);
      if (poolInfo.shares != 0) poolInfo.cashPerShare = cashAmount.div(poolInfo.shares);
    }

    poolInfo.lastTime = now;
  }

  function getUserBalance(address who_, address token_) public view returns(uint256) {
    PoolInfo storage poolInfo = poolMap[token_];
    UserInfo storage userInfo = userMap[who_][token_];

    uint256 totalPerShare = poolInfo.cashPerShare + poolInfo.loanPerShare;
    return totalPerShare.mul(userInfo.shares).div(SHARE_BASE);
  }

  function deposit(address token_, uint256 amount_) external {
    updatePool(token_);

    PoolInfo storage poolInfo = poolMap[token_];
    UserInfo storage userInfo = userMap[_msgSender()][token_];

    // uint256 totalPerShare = poolInfo.cashPerShare + poolInfo.loanPerShare;

    uint256 sharesToAdd = poolInfo.cashPerShare == 0 ? amount_ : amount_.mul(poolInfo.shares).div(userInfo.shares);
    // uint256 loanAmount = poolInfo.loanPerShare.mul(userInfo.shares);

    // Add shares.
    userInfo.shares = userInfo.shares.add(sharesToAdd);
    poolInfo.shares = poolInfo.shares.add(sharesToAdd);

    // Updates loanPerShare.
    // poolInfo.loanPerShare = loanAmount.mul(SHARE_BASE).div(userInfo.shares);

    // No need to update loanPerUnit.

    // Transfers fund to saver.
    IERC20(token_).safeTransferFrom(_msgSender(), registry.saver(), amount_);

    // Re-balance saver and updates cashPerShare.
    ISaver(registry.saver()).rebalance(token_);

    uint256 cashAmount = ISaver(registry.saver()).getAmount(token_);
    
    emit Deposit(msg.sender, cashAmount, sharesToAdd);

    poolInfo.cashPerShare = cashAmount.div(poolInfo.shares);
  }

  function withdraw(address token_, uint256 amount_) external {
    updatePool(token_);

    PoolInfo storage poolInfo = poolMap[token_];
    UserInfo storage userInfo = userMap[_msgSender()][token_];

    require(amount_ <= poolInfo.cashPerShare.mul(poolInfo.shares), "Not enough cash");
    require(amount_ <= getUserBalance(_msgSender(), token_), "Not enough user balance");

    uint256 totalPerShare = poolInfo.cashPerShare + poolInfo.loanPerShare;
    uint256 sharesToRemove = amount_.mul(SHARE_BASE).div(totalPerShare);
    uint256 loanAmount = poolInfo.loanPerShare.mul(userInfo.shares);

    // Remove shares.
    userInfo.shares = userInfo.shares.sub(sharesToRemove);
    poolInfo.shares = poolInfo.shares.sub(sharesToRemove);

    // Updates loanPerShare.
    poolInfo.loanPerShare = loanAmount.mul(SHARE_BASE).div(userInfo.shares);

    // No need to update loanPerUnit.

    // Withdraw from saver.
    ISaver(registry.saver()).withdraw(token_, amount_, _msgSender());

    // Updates cashPerShare.
    uint256 cashAmount = ISaver(registry.saver()).getAmount(token_);
    poolInfo.cashPerShare = cashAmount.div(poolInfo.shares);
  }

  function borrow(address token_, uint256 amount_) external {
    require(_msgSender() == registry.vault(), "Only vault can call");

    updatePool(token_);

    PoolInfo storage poolInfo = poolMap[token_];
    UserInfo storage userInfo = userMap[_msgSender()][token_];

    uint256 cashAmount = ISaver(registry.saver()).getAmount(token_);
    require(amount_ <= cashAmount, "Not enough cash");

    // Updates user's loan units.
    userInfo.loanUnits = userInfo.loanUnits.add(amount_.mul(UNIT_BASE).div(poolInfo.loanPerUnit));

    // Updates loanPerShare.
    poolInfo.loanPerShare = poolInfo.loanPerShare.add(amount_.mul(SHARE_BASE).div(userInfo.shares));

    // No need to update loanPerUnit.

    // Withdraw from saver.
    ISaver(registry.saver()).withdraw(token_, amount_, _msgSender());

    // Updates cashPerShare.
    cashAmount = ISaver(registry.saver()).getAmount(token_);
    poolInfo.cashPerShare = cashAmount.div(poolInfo.shares);
  }

  function payBack(address token_, uint256 amount_) external {
    require(_msgSender() == registry.vault(), "Only vault can call");

    updatePool(token_);

    PoolInfo storage poolInfo = poolMap[token_];
    UserInfo storage userInfo = userMap[_msgSender()][token_];

    // Reduces user's loan units.
    userInfo.loanUnits = userInfo.loanUnits.sub(amount_.mul(UNIT_BASE).div(poolInfo.loanPerUnit));

    // Updates loanPerShare.
    poolInfo.loanPerShare = poolInfo.loanPerShare.sub(amount_.mul(SHARE_BASE).div(userInfo.shares));

    // No need to update loanPerUnit.

    // Transfers fund to saver.
    IERC20(token_).safeTransferFrom(_msgSender(), registry.saver(), amount_);

    // Withdraw from saver.
    ISaver(registry.saver()).rebalance(token_);

    // Updates cashPerShare.
    uint256 cashAmount = ISaver(registry.saver()).getAmount(token_);
    poolInfo.cashPerShare = cashAmount.div(poolInfo.shares);
  }
}
