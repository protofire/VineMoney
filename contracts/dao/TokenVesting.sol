// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "../dependencies/VineOwnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenVesting is VineOwnable {
    address public immutable vault;
    IERC20 public immutable VINE;

    mapping(address => UnlockingRules) public UnlockingInfo;
    uint256 public duration;
    uint256 public unlockingStartTime;

    event SetUnlockingRule(
        address indexed _addr,
        uint256 _totalLocked,
        uint256 _duration,
        uint256 _unlockingStartTime,
        uint256 _lastUnlockingTime
    );

    event Vest(address indexed _addr, address to, uint256 _amount);

    constructor(address _vineCore, address _vault, IERC20 _VINE) VineOwnable(_vineCore) {
        vault = _vault;
        VINE = _VINE;
    }

    struct UnlockingRules {
        uint256 totalLocked;
        uint256 duration;
        uint256 unlockingStartTime;
        uint256 lastUnlockingTime;
    }

    function setUnlockingRule(
        address _addr,
        uint256 _totalLocked,
        uint256 _duration,
        uint256 _unlockingStartTime
    ) external onlyOwner {
        require(
            UnlockingInfo[_addr].lastUnlockingTime == 0,
            "The rule has already been set."
        );
        UnlockingInfo[_addr].totalLocked = _totalLocked;
        UnlockingInfo[_addr].duration = _duration;
        UnlockingInfo[_addr].unlockingStartTime = _unlockingStartTime;
        UnlockingInfo[_addr].lastUnlockingTime = _unlockingStartTime;

        emit SetUnlockingRule(
            _addr,
            _totalLocked,
            _duration,
            _unlockingStartTime,
            _unlockingStartTime
        );
    }

    function getUnlockableAmount(address addr) public view returns (uint256) {
        if (block.timestamp <= UnlockingInfo[addr].unlockingStartTime) return 0;

        uint256 unlockingEndTime = UnlockingInfo[addr].unlockingStartTime +
            UnlockingInfo[addr].duration;
        uint256 elapsedTime = 0;
        if (UnlockingInfo[addr].lastUnlockingTime == 0) {
            elapsedTime = block.timestamp > unlockingEndTime
                ? (unlockingEndTime - UnlockingInfo[addr].unlockingStartTime)
                : (block.timestamp - UnlockingInfo[addr].unlockingStartTime);
        } else {
            elapsedTime = block.timestamp > unlockingEndTime
                ? (unlockingEndTime - UnlockingInfo[addr].lastUnlockingTime)
                : (block.timestamp - UnlockingInfo[addr].lastUnlockingTime);
        }

        return
            (elapsedTime * UnlockingInfo[addr].totalLocked) /
            UnlockingInfo[addr].duration;
    }

    function vest(address to) external {
        require(
            block.timestamp >= UnlockingInfo[msg.sender].unlockingStartTime,
            "The unlocking time has not arrived yet."
        );

        uint256 unlockableAmount = getUnlockableAmount(msg.sender);

        if (unlockableAmount > 0) {
            uint256 unlockingEndTime = UnlockingInfo[msg.sender]
                .unlockingStartTime + UnlockingInfo[msg.sender].duration;
            if (block.timestamp > unlockingEndTime) {
                UnlockingInfo[msg.sender].lastUnlockingTime = unlockingEndTime;
            } else {
                UnlockingInfo[msg.sender].lastUnlockingTime = block.timestamp;
            }
            VINE.transferFrom(vault, to, unlockableAmount);
            emit Vest(msg.sender, to, unlockableAmount);
        }
    }
}
