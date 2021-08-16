pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/IInterestModel.sol";

contract BasicModel is IInterestModel {
  using SafeMath for uint256;

  uint256 public constant RATE_BASE = 1e8;

  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(
      uint256 saverRate_,
      uint256 cashPerShare_,
      uint256 loanPerShare_
  ) external override pure returns (uint256) {
    if (loanPerShare_.mul(10) < cashPerShare_.add(loanPerShare_).mul(8)) {
      // Utilization < 80%
      return saverRate_.add(5e5);  // 0.5%
    } else {
      // Utilization >= 80%
      return loanPerShare_.mul(10).mul(RATE_BASE).div(
          cashPerShare_.add(loanPerShare_)).sub(8).add(
              saverRate_).add(5e5);
    }
  }
}
