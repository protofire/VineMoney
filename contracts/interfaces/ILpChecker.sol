// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILpChecker {
    function getLpVault(address account) external view returns (uint256);
    function checkDlpStatus(uint256 debt, address account) external view returns (bool);
    function dlpBonus() external view returns (uint256);
}
