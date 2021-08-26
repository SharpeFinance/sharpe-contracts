pragma solidity 0.6.12;

interface IAdaptor {
  function getName() external view returns(string calldata);
  function deposit(address token_) external payable returns (uint256);
  function withdraw(address token_, uint256 _amount) external returns (uint256);
  function getRate(address token_) external view returns(uint256);
  function nextSupplyRate(address token_, uint256 amount) external view returns (uint256);
  function getAmount(address token_) external view returns (uint256);
  function getPriceInToken(address token_) external view returns (uint256);
  function availableLiquidity(address token_) external view returns (uint256);
}
