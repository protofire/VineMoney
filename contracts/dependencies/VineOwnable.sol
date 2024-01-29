// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "../interfaces/IVineCore.sol";

/**
    @title Vine Ownable
    @notice Contracts inheriting `VineOwnable` have the same owner as `VineCore`.
            The ownership cannot be independently modified or renounced.
 */
contract VineOwnable {
    IVineCore public immutable VINE_CORE;

    constructor(address _vineCore) {
        VINE_CORE = IVineCore(_vineCore);
    }

    modifier onlyOwner() {
        require(msg.sender == VINE_CORE.owner(), "Only owner");
        _;
    }

    function owner() public view returns (address) {
        return VINE_CORE.owner();
    }

    function guardian() public view returns (address) {
        return VINE_CORE.guardian();
    }
}
