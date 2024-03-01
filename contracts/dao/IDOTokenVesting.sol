// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "../dependencies/VineOwnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IDOTokenVesting is VineOwnable {
    address public immutable vault;
    IERC20 public immutable VINE;

    mapping(address => UnlockingRules) public UnlockingInfo;
    uint256 public duration;
    uint256 public unlockingStartTime;

    event Vest(address indexed _addr, address t0, uint256 _amount);
    event ClaimAirdrop(
        address indexed _addr,
        uint256 _amount
    );


    constructor(address _vineCore, address _vault, IERC20 _VINE) VineOwnable(_vineCore) {
        vault = _vault;
        VINE = _VINE;
    }

    struct UnlockingRules {
        uint256 airdrop;
        bool isClaimed;
        uint256 totalLocked;
        uint256 lastUnlockingTime;
    }

    function setUnlockingRule(
        address[] calldata _addrs,
        uint256[] calldata _totalLockeds,
        uint256[] calldata _airdrops
    ) external onlyOwner {
        require(_addrs.length == _totalLockeds.length);
        for (uint256 i = 0; i < _addrs.length; i++) {
            require(
                UnlockingInfo[_addrs[i]].lastUnlockingTime == 0,
                "The rule has already been set."
            );
            UnlockingInfo[_addrs[i]].totalLocked = _totalLockeds[i];
            UnlockingInfo[_addrs[i]].airdrop = _airdrops[i];
        }
    }

    function getUnlockableAmount(address addr) public view returns (uint256) {
        if (block.timestamp <= unlockingStartTime) return 0;

        uint256 unlockingEndTime = unlockingStartTime + duration;
        uint256 elapsedTime = 0;
        if (UnlockingInfo[addr].lastUnlockingTime == 0) {
            elapsedTime = block.timestamp > unlockingEndTime
                ? (unlockingEndTime - unlockingStartTime)
                : (block.timestamp - unlockingStartTime);
        } else {
            elapsedTime = block.timestamp > unlockingEndTime
                ? (unlockingEndTime - UnlockingInfo[addr].lastUnlockingTime)
                : (block.timestamp - UnlockingInfo[addr].lastUnlockingTime);
        }

        return (elapsedTime * UnlockingInfo[addr].totalLocked) / duration;
    }

    function vest(address to) external {
        require(
            block.timestamp >= unlockingStartTime,
            "The unlocking time has not arrived yet."
        );
        
        uint256 unlockableAmount = getUnlockableAmount(msg.sender);

        if (unlockableAmount > 0) {
            uint256 unlockingEndTime = unlockingStartTime + duration;
            if (block.timestamp > unlockingEndTime) {
                UnlockingInfo[msg.sender].lastUnlockingTime = unlockingEndTime;
            } else {
                UnlockingInfo[msg.sender].lastUnlockingTime = block.timestamp;
            }
            VINE.transferFrom(vault, to, unlockableAmount);
            emit Vest(msg.sender, to, unlockableAmount);
        }
    }

    function claimAirdrop() external {
        require(
            block.timestamp >= unlockingStartTime,
            "The time has not arrived yet."
        );
        require(
            !UnlockingInfo[msg.sender].isClaimed,
            "You have already claimed it."
        );
        uint256 amount = UnlockingInfo[msg.sender].airdrop;
        require(amount > 0, "You are not eligible for the airdrop.");
        VINE.transferFrom(vault, msg.sender, amount);
        UnlockingInfo[msg.sender].isClaimed = true;
        emit ClaimAirdrop(msg.sender, amount);
    }
}
