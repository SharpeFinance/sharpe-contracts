// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/ISaver.sol";

// This contract is owned by Timelock.
contract Saver is ISaver, Ownable {

  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  uint256 constant SHARE_BASE = 1e18;
  uint256 constant RATE_BASE = 1e8;

  function getRate(address token_) external override view returns(uint256) {
    return 0;
  }

  function getAmount(address token_) external override view returns(uint256) {
    return 0;
  }

  function rebalance(address token_) external override {
  }

  function withdraw(address token_, uint256 amount_, address toAddress_) external override {
  }
}
