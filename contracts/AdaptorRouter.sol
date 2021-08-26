pragma solidity 0.6.12;

contract AdaptorRouter {
  // baseToken => adaptorName => address;
  mapping(address => mapping(string => address)) public getPair;
  address public wrappedNativeAddr;

  function addPair(address baseToken, string memory adaptorName, address valutAddr)
    external {
      getPair[baseToken][adaptorName] = valutAddr;
  }

  function getWrappedNativeAddr()
    external view
    returns (address) {
    return wrappedNativeAddr;
  }

 function setWrappedNativeAddr(address adr)
    external
    returns (address) {
      wrappedNativeAddr = adr;
  }

}