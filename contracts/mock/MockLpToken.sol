// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockLpToken is ERC20 {
    string internal constant _NAME = "Lp Token";
    string internal constant _SYMBOL = "LP";

    constructor() ERC20(_NAME, _SYMBOL) {
        _mint(msg.sender, 1e22);
    }
}
