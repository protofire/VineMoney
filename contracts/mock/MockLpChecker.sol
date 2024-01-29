// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

contract LpChecker is Ownable {
    uint256 public dlpThresold;
    uint256 public dlpBonus;

    constructor() Ownable(msg.sender) {

    }

    function setDlpParams(uint256 _dlpThresold, uint256 _dlpBonus) external onlyOwner {
        require(_dlpBonus < 1000, "OR");
        dlpThresold = _dlpThresold;
        dlpBonus = _dlpBonus;
    }

    function checkDlpStatus(uint256 debt, address account) public view returns (bool) {
        if(debt == 0) return false;
        if(getLpVault(account) * 1000 / debt > dlpThresold) return true;
        return false;
    }

    function getLpVault(address account) public view returns (uint256) {

    }
}
