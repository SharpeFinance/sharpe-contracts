pragma solidity 0.6.12;

import "./interfaces/IRebalancer.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Rebalancer is IRebalancer, Ownable {
  using SafeMath for uint256;

  uint256[] public lastAmounts;
  address[] public lastAmountsAddresses;

  address public rebalancerManager;
  address public saver;

  constructor(address vToken, address aToken, address _rebalancerManager) public {
    require(vToken != address(0) && aToken != address(0) && _rebalancerManager != address(0), 'some addr is 0');
    rebalancerManager = _rebalancerManager;

    lastAmounts = [100000, 0];
    lastAmountsAddresses = [vToken, aToken];
  }

  modifier onlyRebalancerAndSaver() {
    require(msg.sender == rebalancerManager || msg.sender == saver, "Only rebalacer and saver");
    _;
  }

  function setRebalancerManager(address _rebalancerManager)
    external onlyOwner {
      require(_rebalancerManager != address(0), "_rebalancerManager addr is 0");

      rebalancerManager = _rebalancerManager;
  }

  function setSaver(address _saver)
    external onlyOwner {
      require(saver == address(0), "saver addr already set");
      require(_saver != address(0), "_saver addr is 0");
      saver = _saver;
  }

  function setNewToken(address _newToken)
    external onlyOwner {
      require(_newToken != address(0), "New token should be != 0");
      for(uint256 i = 0; i < lastAmountsAddresses.length; i++) {
        if (lastAmountsAddresses[i] == _newToken) {
          return;
        }
      }

      lastAmountsAddresses.push(_newToken);
      lastAmounts.push(0);
  }

  function setAllocations(uint256[] calldata _allocations, address[] calldata _addresses)
    external override onlyRebalancerAndSaver {
      require(_allocations.length == lastAmounts.length, "length != allocations");
      require(_allocations.length == _addresses.length, "length != _addresses");

      uint256 total;
      for(uint256 i = 0; i < _allocations.length; i++) {
        require(_addresses[i] == lastAmountsAddresses[i], "Address not match");
        total = total.add(_allocations[i]);
        lastAmounts[i] = _allocations[i];
      }
      require(total == 100000, "NOT 100%");
  }

  function getAllocations()
    external view override returns (uint256[] memory _allocations){
      return lastAmounts;
  }

}