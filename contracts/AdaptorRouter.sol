pragma solidity 0.6.12;

contract AdaptorRouter {

  // baseToken => adaptorName => address;
  mapping(address => mapping(string => address)) public getPair;
  
  function initialize() public {

    // // BNB - aplapac
    // getPair[address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c)]["AlpacaAdaptor"] 
    //   = address(0xd7d069493685a581d27824fc46eda46b7efc0063);

    //  // BNB - venus
    // getPair[address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c)]["VenusAdaptor"] 
    //   = address(0xa07c5b74c9b40447a954e1466938b865b6bbea36);
  }

  function addPair(address baseToken, string memory adaptorName, address valutAddr) 
    external {
      getPair[baseToken][adaptorName] = valutAddr;
  }
}