// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract owned {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
    }

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner,"user not is owner");
        _;
    }
}
