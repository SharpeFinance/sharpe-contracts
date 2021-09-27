pragma solidity 0.6.12;

interface IRebalancer {
  function getAllocations() external view returns (uint256[] memory _allocations);
  function setAllocations(uint256[] calldata _allocations, address[] calldata _addresses) external;
}
