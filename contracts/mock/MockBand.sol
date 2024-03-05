// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

contract LPPriceOracle is Ownable {
    uint256 price;
    struct ReferenceData {
        uint256 rate; // base/quote exchange rate, multiplied by 1e18.
        uint256 lastUpdatedBase; // UNIX epoch of the last time when base price gets updated.
        uint256 lastUpdatedQuote; // UNIX epoch of the last time when quote price gets updated.
    }

    constructor(uint256 _price) Ownable(msg.sender) {
        price = _price;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    /// Returns the price data for the given base/quote pair. Revert if not available.
    function getReferenceData(string memory, string memory)
        external
        view
        virtual
        returns (ReferenceData memory data) {
            data.rate = price;
            data.lastUpdatedBase = block.timestamp - 1;
            data.lastUpdatedQuote = block.timestamp - 1;
        }
}
