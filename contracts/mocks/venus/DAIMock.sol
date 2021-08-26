pragma solidity 0.6.12;

// interfaces
// import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./ERC20Detailed.sol";

// ERC20Detailed('DAI', 'DAI', 18) 
contract DAIMock is ERC20 {
  constructor() ERC20("DAI", "DAI")
    public {
    _mint(address(this), 10**24); // 1.000.000 DAI
    _mint(msg.sender, 10**22); // 10.000 DAI
  }
}
