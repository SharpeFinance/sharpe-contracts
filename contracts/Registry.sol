// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IRegistry.sol";

contract Registry is Ownable, IRegistry {

  uint256 public override constant SHARE_BASE = 1e18;
  uint256 public override constant UNIT_BASE = 1e18;
  uint256 public override constant RATE_BASE = 1e8;

  address public override interestModel;
  address public override saver;
  address public override bank;
  address public override vault;
  address public override pancake;

  function setInterestModel(address interestModel_) external onlyOwner {
    interestModel = interestModel_;
  }

  function setSaver(address saver_) external onlyOwner {
    saver = saver_;
  }

  function setBank(address bank_) external onlyOwner {
    bank = bank_;
  }

  function setVault(address vault_) external onlyOwner {
    vault = vault_;
  }

  function setPancake(address pancake_) external onlyOwner {
    pancake = pancake_;
  }
}
