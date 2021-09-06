// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakeFactory.sol";
import "@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakePair.sol";

import "./interfaces/IRegistry.sol";
import "./interfaces/pancake/IPancakeRouter02.sol";
import "./SafeToken.sol";

interface IBank {
  function borrow(address token_, uint256 amount_) external;
  function payBack(address token_, uint256 amount_ ) external;
}

// This contract is owned by Timelock.
contract Vault is Ownable {

  using SafeToken for address;
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
    PairInfo memory pairInfo = pairInfoMap[pairId_];
    address baseToken = pairInfo.token0;
    address farmingToken = pairInfo.token1;
    // Initliaze router and path
    IPancakeRouter02 router = IPancakeRouter02(registry.pancake());
    address[] memory path = new address[](1);
    path[0] = baseToken;
    path[0] = farmingToken;

    // Get Price of baseToken to farmingToken
    uint256 amountIn = 1 ** 18;
    uint256[] memory amountOuts = router.getAmountsOut(amountIn, path);

    return amountOuts[0].mul(PRICE_BASE);
  }

  function getPriceNearBy(uint256 pairId_) public view returns(uint256[] memory) {
      uint256 priceLimit = 20;  // size of price
      uint256 stepPercent = 2;  // 2% percent of currentPrice

      uint256 currentPrice = getPrice(pairId_);
      uint256[] memory nearPrices = new uint256[](priceLimit);
      uint256 stepPrice = currentPrice.mul(100).mul(stepPercent).div(10000); // currentPrice * 0.02

      uint256 startOffset = priceLimit.div(2).sub(1); // priceLimit / 2 - 1
      uint256 cursorPrice = currentPrice.sub(stepPrice.mul(startOffset));

      for (uint8 index = 0; index < priceLimit; index++) {
        nearPrices[index] = cursorPrice;
        cursorPrice = cursorPrice.add(stepPrice);
      }

      return nearPrices;
  }

  function findAvailableIndex(uint256 pairId_, address who_) public view returns(uint256) {
    return allPositions[who_][pairId_].length;
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

  function _borrowAndAddLiquidity(uint256 pairId_, uint256 amount0_) private returns(uint256 lpAmount) {

    PairInfo memory pairInfo = pairInfoMap[pairId_];
    address baseToken = pairInfo.token0;
    address farmingToken = pairInfo.token1;

    // 1. Initliaze factory and router
    IPancakeRouter02 router = IPancakeRouter02(registry.pancake());
    IPancakeFactory factory = IPancakeFactory(router.factory());
    // IPancakePair lpToken = IPancakePair(factory.getPair(baseToken, farmingToken));

    // 2. Approve router to do their stuffs
    farmingToken.safeApprove(address(router), uint256(-1));
    baseToken.safeApprove(address(router), uint256(-1));

    // 3. Borrow token1 from bank
    IBank(registry.bank()).borrow(farmingToken, amount0_);

    // 4. Mint LP Token
    (, , uint256 moreLPAmount) = router.addLiquidity(
        baseToken,
        farmingToken,
        baseToken.myBalance(),
        farmingToken.myBalance(),
        0,
        0,
        address(this),
        now
      );

    lpAmount = moreLPAmount;
    // 5. Reset approval for safety reason
    baseToken.safeApprove(address(router), 0);
    farmingToken.safeApprove(address(router), 0);
  }

  function _removeLiquidity(uint256 pairId_, uint256 lpAmount_) private returns(uint256) {

    PairInfo memory pairInfo = pairInfoMap[pairId_];
    address baseToken = pairInfo.token0;
    address farmingToken = pairInfo.token1;

    // 1. Initliaze factory and router
    IPancakeRouter02 router = IPancakeRouter02(registry.pancake());
    IPancakeFactory factory = IPancakeFactory(router.factory());

    // 2. Approve router to do their stuffs
    IPancakePair lpToken = IPancakePair(factory.getPair(farmingToken, baseToken));
    require(lpToken.approve(address(router), uint256(-1)), "Vault::_removeLiquidity:: unable to approve LP token");

    // 3. Remove all liquidity back to BaseToken and farming tokens.
    (uint256 amountA, uint256 amountB) = router.removeLiquidity(
        baseToken,
        farmingToken,
        lpAmount_,
        0,
        0,
        address(this),
        now
      );

    // 4. Payback farmingToken to bank
    IBank(registry.bank()).payBack(farmingToken, amountB);
    return amountA;
  }
}
