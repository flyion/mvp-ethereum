pragma solidity ^0.5.2;

import '@openzeppelin/contracts/ownership/Ownable.sol';

contract Authorizable is Ownable {

    mapping(address => bool) public authorized;
    address[] public authorizedList;


    modifier onlyAuthorized() {
        require(authorized[msg.sender] || owner() == msg.sender);
        _;
    }

    function addAuthorized(address _toAdd) onlyOwner public {
        require(_toAdd != address(0));
        authorized[_toAdd] = true;
        authorizedList.push(_toAdd); //push address in the array of authorized addresses
    }

    function removeAuthorized(address _toRemove) onlyOwner public {
        require(_toRemove != address(0));
        require(_toRemove != msg.sender);
        authorized[_toRemove] = false;
    }

    function removeAllAuthorized() onlyOwner public {
        uint iMax = getNbAuthorizedAddresses();
        for (uint i=0; i<iMax; i++) {authorized[authorizedList[i]] = false;}
        delete authorizedList;
        addAuthorized(msg.sender);
    }
    function getNbAuthorizedAddresses() public view returns(uint count) {
        return authorizedList.length;
    }
}