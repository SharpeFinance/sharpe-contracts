pragma solidity 0.6.12;

interface IRegistry {

  function SHARE_BASE() external pure returns(uint256);
  function UNIT_BASE() external pure returns(uint256);
  function RATE_BASE() external pure returns(uint256);

  function interestModel() external view returns(address);
  function saver() external view returns(address);
  function bank() external view returns(address);
  function vault() external view returns(address);
}
