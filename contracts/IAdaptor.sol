pragma solidity 0.6.12;

// interface LendingProtocol {
//   function mint() external returns (uint256);
//   function redeem(address account) external returns (uint256);
//   function nextSupplyRate(uint256 amount) external view returns (uint256);
  
//   function getAPR() external view returns (uint256);
//   function getPriceInToken() external view returns (uint256);
//   function token() external view returns (address);
//   function underlying() external view returns (address);
//   function availableLiquidity() external view returns (uint256);
// }

interface IAdaptor {

  function getName() external view returns(string calldata);

  function deposit(address token_) external returns (uint256);
  function withdraw(address token_, uint256 _amount) external returns (uint256);

  function getRate(address token_) external view returns(uint256);

  // function getAPR(address token_) external view returns (uint256);
  function nextSupplyRate(address token_, uint256 amount) external view returns (uint256);

  function getAmount(address token_) external view returns (uint256);

  function getPriceInToken(address token_) external view returns (uint256);

  function availableLiquidity(address token_) external view returns (uint256);
}
