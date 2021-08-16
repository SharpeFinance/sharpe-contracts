pragma solidity 0.6.12;

interface IInterestModel {
  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(
      uint256 saverRate_,
      uint256 cashPerShare_,
      uint256 loanPerShare_
  ) external pure returns (uint256);
}
