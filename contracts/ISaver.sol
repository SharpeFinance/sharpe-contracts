pragma solidity 0.6.12;

interface ISaver {
  function getRate(address token_) external view returns(uint256);
  function getAmount(address token_) external view returns(uint256);
  function rebalance(address token_) external;
  function withdraw(address token_, uint256 amount_, address toAddress_) external;
}
