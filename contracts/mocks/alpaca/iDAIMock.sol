pragma solidity 0.6.12;

// interfaces
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
// import "../interfaces/CERC20.sol";

interface AlpacaValut {
  /// @dev Return the total ERC20 entitled to the token holders. Be careful of unaccrued interests.
  // function totalToken() external view returns (uint256);

  /// @dev Add more ERC20 to the bank. Hope to get some good returns.
  function deposit(uint256 amountToken) external payable;

  /// @dev Withdraw ERC20 from the bank by burning the share tokens.
  function withdraw(uint256 share) external;

  /// @dev Request funds from user through Vault
  // function requestFunds(address targetedToken, uint amount) external;

  // function token() external view returns (address);
  // function config() external view returns (address);
  // function vaultDebtVal() external view returns (uint256);
  // function reservePool() external view returns (uint256);

  function totalToken() external view returns (uint256);
  // function totalSupply() external view returns (uint256);
}

contract iDAIMock is AlpacaValut, ERC20 {

  using SafeMath for uint256;

  address public dai;

  uint256 public vaultDebtShare;
  uint256 public vaultDebtVal;
  uint256 public lastAccrueTime;
  uint256 public reservePool;
  address public config;

// ERC20Detailed('cDAI', 'cDAI', 8)
  constructor(address _dai, address tokenOwner, address _config)
    ERC20("iDAI", "iDAI")
     public {
    dai = _dai;
    config = _config;
    vaultDebtVal = 0;
    reservePool = 0;
    _mint(address(this), 10**18); // 1.000.000 cDAI
    _mint(tokenOwner, 10**18); // 100.000 cDAI
  }

  function setVaultDebtVal(uint256 amount) public {
    vaultDebtVal = amount;
  }

  function totalToken() public view override returns (uint256) {
    // return balanceOf(address(this)).add(vaultDebtVal).sub(reservePool);
    return IERC20(dai).balanceOf(address(this));
  }

  function deposit(uint256 amount) external payable override {
    require(IERC20(dai).transferFrom(msg.sender, address(this), amount), "Error during transferFrom"); // 1 DAI
    uint256 total = totalToken().sub(amount);
    uint256 share = total == 0 ? amount : amount.mul(totalSupply()).div(total);
    _mint(msg.sender, share);
  }

  function withdraw(uint256 share) external override {
    uint256 amount = share.mul(totalToken()).div(totalSupply());
    _burn(msg.sender, share);
    require(IERC20(dai).transfer(msg.sender, amount), "Error during transfer"); // 1 DAI
  }
}
