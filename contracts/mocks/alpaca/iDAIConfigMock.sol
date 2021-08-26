interface IVaultConfig {
  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256);
  /// @dev Return the bps rate for reserve pool.
  function getReservePoolBps() external view returns (uint256);
}

interface InterestModel {
  /// @dev Return the interest rate per second, using 1e18 as denom.
  function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256);
}

contract iDAIConfigMock is IVaultConfig {
  InterestModel public interestModel;
  uint256 public override getReservePoolBps;

  constructor (address model) public {
    interestModel = InterestModel(model);
    getReservePoolBps = 0;
  } 

  function getInterestRate(uint256 debt, uint256 floating) 
    external view override
    returns (uint256) {
      return interestModel.getInterestRate(debt, floating);
  }
}
