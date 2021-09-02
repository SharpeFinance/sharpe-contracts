// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakeFactory.sol";
import "@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakePair.sol";

import "./interfaces/IRegistry.sol";
import "./apis/pancakeV2/PancakeRouterV2.sol";

interface IBank {
  function borrow(address token_, uint256 amount_) external;
  function payBack(address token_, uint256 amount_ ) external;
}

// This contract is owned by Timelock.
contract Vault is Ownable {

  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  uint256 constant PRICE_BASE = 1e18;

  // Order of token0 and token1 matters.
  struct PairInfo {
    address token0;
    address token1;
  }

  // pairId => PairInfo
  mapping(uint256 => PairInfo) public pairInfoMap;

  // pairId => price => amount-to-reduce
  mapping(uint256 => mapping(uint256 => uint256)) public lowAmount;
  mapping(uint256 => mapping(uint256 => uint256)) public highAmount;

  struct Exit {
    uint256 amount0;  // Obtained amount of token0.
    uint256 lpAmount;  // Decomposited amount.
  }

  // pairId => price => Exit[]
  mapping(uint256 => mapping(uint256 => Exit[])) public lowExit;
  mapping(uint256 => mapping(uint256 => Exit[])) public highExit;

  struct Position {
    uint256 lpAmount;
    uint256 lowPrice;
    uint256 highPrice;
    uint256 lowIndex;  // The low exit index.
    uint256 highIndex;  // The low exit index.
  }

  // who => pairId => index => Position
  mapping(address => mapping(uint256 => mapping(uint256 => Position))) public allPositions;

  IRegistry public registry;

  constructor (IRegistry registry_) public {
    registry = registry_;
  }

  function getPrice(uint256 pairId_) public view returns(uint256) {
  }

  function getPriceNearBy(uint256 pairId_) public view returns(uint256 [] memory) {
  }

  function findAvailableIndex(uint256 pairId_, address who_) public view returns(uint256) {
    return 0;
  }

  function _checkInRange(uint256 pairId_, uint256 lowPrice_, uint256 highPrice_) private {
    uint256 price = getPrice(pairId_);

    require(price > lowPrice_, "> lowPrice");
    require(price < highPrice_, "< highPrice");
  }

  function create(uint256 pairId_, uint256 amount0_, uint256 lowPrice_, uint256 highPrice_) external returns(uint256) {
    _checkInRange(pairId_, lowPrice_, highPrice_);

    PairInfo storage pairInfo = pairInfoMap[pairId_];
    IERC20(pairInfo.token0).safeTransferFrom(_msgSender(), address(this), amount0_);

    // Provides token0 and borrow token1.
    uint256 lpAmount = _borrowAndAddLiquidity(pairId_, amount0_);

    // Adds to lowAmount and highAmount.
    lowAmount[pairId_][lowPrice_] = lowAmount[pairId_][lowPrice_].add(lpAmount);
    highAmount[pairId_][highPrice_] = highAmount[pairId_][highPrice_].add(lpAmount);

    uint256 index = findAvailableIndex(pairId_, _msgSender());

    // Creates position.
    Position storage position = allPositions[_msgSender()][pairId_][index];
    position.lpAmount = lpAmount;
    position.lowPrice = lowPrice_;
    position.highPrice = highPrice_;
    position.lowIndex = lowExit[pairId_][lowPrice_].length;
    position.highIndex = highExit[pairId_][highPrice_].length;

    return index;
  }

  function increase(uint256 pairId_, uint256 index_, uint256 amount0_) external {
    Position storage position = allPositions[_msgSender()][pairId_][index_];
    _checkInRange(pairId_, position.lowPrice, position.highPrice);

    PairInfo storage pairInfo = pairInfoMap[pairId_];
    IERC20(pairInfo.token0).safeTransferFrom(_msgSender(), address(this), amount0_);

    // Provides token0 and borrow token1.
    uint256 lpAmount = _borrowAndAddLiquidity(pairId_, amount0_);

    // Adds to lowAmount and highAmount.
    lowAmount[pairId_][position.lowPrice] = lowAmount[pairId_][position.lowPrice].add(lpAmount);
    highAmount[pairId_][position.highPrice] = highAmount[pairId_][position.highPrice].add(lpAmount);

    // Adds to position.
    position.lpAmount = position.lpAmount.add(lpAmount);
  }

  function decrease(uint256 pairId_, uint256 index_, uint256 lpAmount_) external {
    Position storage position = allPositions[_msgSender()][pairId_][index_];

    require(position.lpAmount >= lpAmount_, "decrease more than you have");

    _checkInRange(pairId_, position.lowPrice, position.highPrice);

    // Decompose LP and obtain token0.
    uint256 amount0 = _removeLiquidity(pairId_, lpAmount_);

    PairInfo storage pairInfo = pairInfoMap[pairId_];
    IERC20(pairInfo.token0).safeTransfer(_msgSender(), amount0);

    // Substracts from lowAmount and highAmount.
    lowAmount[pairId_][position.lowPrice] = lowAmount[pairId_][position.lowPrice].sub(lpAmount_);
    highAmount[pairId_][position.highPrice] = highAmount[pairId_][position.highPrice].sub(lpAmount_);

    // Substracts from position.
    position.lpAmount = position.lpAmount.sub(lpAmount_);
  }

  // Anyone can call this function for bonus.
  function stop(uint256 pairId_) external {
    uint256 price = getPrice(pairId_);
    uint256[] memory priceArray = getPriceNearBy(pairId_);
    for (uint256 i = 0; i < priceArray.length; ++i) {
      _stop(pairId_, price, priceArray[i]);
    }
  }

  function _stop(uint256 pairId_, uint256 currentPrice_, uint256 pointPrice_) private {
    if (currentPrice_ <= pointPrice_) {
      _decomposite(pairId_, lowAmount[pairId_][pointPrice_], pointPrice_, true);
      lowAmount[pairId_][pointPrice_] = 0;
    }

    if (currentPrice_ >= pointPrice_) {
      _decomposite(pairId_, highAmount[pairId_][pointPrice_], pointPrice_, false);
      highAmount[pairId_][pointPrice_] = 0;
    }
  }

  function _decomposite(uint256 pairId_, uint256 lpAmount_, uint256 price_, bool isLow_) private {
    // Decompose LP and obtain token0.
    uint256 amount0 = _removeLiquidity(pairId_, lpAmount_);

    if (isLow_) {
      lowExit[pairId_][price_].push(Exit(amount0, lpAmount_));
    } else {
      highExit[pairId_][price_].push(Exit(amount0, lpAmount_));
    }
  }

  function transferAfterStop() external {
  }

  function _borrowAndAddLiquidity(uint256 pairId_, uint256 amount0_) private returns(uint256) {

    PairInfo memory pairInfo = pairInfoMap[pairId_];

    // borrow from bank
    IBank(registry.brank()).borrow(pairInfo.token1, amount0_);

    address router = address(0);
    


  }

  function _removeLiquidity(uint256 pairId_, uint256 lpAmount_) private returns(uint256) {
    return 0;
  }
}
