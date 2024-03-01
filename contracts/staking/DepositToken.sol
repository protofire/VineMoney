// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/IVault.sol";
import "../dependencies/VineOwnable.sol";

/**
    @title Vine Deposit Wrapper
 */
contract DepositToken is VineOwnable {
    IERC20 public immutable VINE;
    IVineVault public immutable vault;

    IERC20 public lpToken;

    uint256 public emissionId;

    string public symbol;
    string public name;
    uint256 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // each array relates to VINE
    uint256 public rewardIntegral;
    uint128 public rewardRate;
    uint32 public lastUpdate;
    uint32 public periodFinish;

    // maximum percent of weekly emissions that can be directed to this receiver,
    // as a whole number out of 10000. emissions greater than this amount are stored
    // until `Vault.lockWeeks() == 0` and then returned to the unallocated supply.
    uint16 public maxWeeklyEmissionPct;
    uint128 public storedExcessEmissions;

    mapping(address => uint256) public rewardIntegralFor;
    mapping(address => uint128) private storedPendingReward;

    uint256 constant REWARD_DURATION = 1 weeks;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event LPTokenDeposited(address indexed lpToken, address indexed receiver, uint256 amount);
    event LPTokenWithdrawn(address indexed lpToken, address indexed receiver, uint256 amount);
    event RewardClaimed(address indexed receiver, uint256 vineAmount);
    event MaxWeeklyEmissionPctSet(uint256 pct);
    event MaxWeeklyEmissionsExceeded(uint256 allocated, uint256 maxAllowed);

    constructor(
        IERC20 _vine,
        IERC20 _lpToken,
        IVineVault _vault,
        address vineCore
    ) VineOwnable(vineCore) {
        VINE = _vine;
        lpToken = _lpToken;
        vault = _vault;
        VINE.approve(address(vault), type(uint256).max);
        string memory _symbol = IERC20Metadata(address(_lpToken)).symbol();
        name = string.concat("Vine ", _symbol, " Deposit");
        symbol = string.concat("vine-", _symbol);

        periodFinish = uint32(block.timestamp - 1);
        maxWeeklyEmissionPct = 10000;
        emit MaxWeeklyEmissionPctSet(10000);
    }

    function setMaxWeeklyEmissionPct(uint16 _maxWeeklyEmissionPct) external onlyOwner returns (bool) {
        require(_maxWeeklyEmissionPct < 10001, "Invalid maxWeeklyEmissionPct");
        maxWeeklyEmissionPct = _maxWeeklyEmissionPct;

        emit MaxWeeklyEmissionPctSet(_maxWeeklyEmissionPct);
        return true;
    }

    function notifyRegisteredId(uint256[] memory assignedIds) external returns (bool) {
        require(msg.sender == address(vault));
        require(emissionId == 0, "Already registered");
        require(assignedIds.length == 1, "Incorrect ID count");
        emissionId = assignedIds[0];

        return true;
    }

    function deposit(address receiver, uint256 amount) external returns (bool) {
        require(amount > 0, "Cannot deposit zero");
        lpToken.transferFrom(msg.sender, address(this), amount);
        uint256 balance = balanceOf[receiver];
        uint256 supply = totalSupply;
        balanceOf[receiver] = balance + amount;
        totalSupply = supply + amount;

        _updateIntegrals(receiver, balance, supply);
        if (block.timestamp / 1 weeks >= periodFinish / 1 weeks) _fetchRewards();

        emit Transfer(address(0), receiver, amount);
        emit LPTokenDeposited(address(lpToken), receiver, amount);
        return true;
    }

    function withdraw(address receiver, uint256 amount) external returns (bool) {
        require(amount > 0, "Cannot withdraw zero");
        uint256 balance = balanceOf[msg.sender];
        uint256 supply = totalSupply;
        balanceOf[msg.sender] = balance - amount;
        totalSupply = supply - amount;
        lpToken.transfer(receiver, amount);

        _updateIntegrals(msg.sender, balance, supply);
        if (block.timestamp / 1 weeks >= periodFinish / 1 weeks) _fetchRewards();

        emit Transfer(msg.sender, address(0), amount);
        emit LPTokenWithdrawn(address(lpToken), receiver, amount);

        return true;
    }

    function _claimReward(address claimant, address) internal returns (uint128 amounts) {
        _updateIntegrals(claimant, balanceOf[claimant], totalSupply);
        amounts = storedPendingReward[claimant];
        delete storedPendingReward[claimant];

        return amounts;
    }

    function claimReward(address receiver) external returns (uint256 vineAmount) {
        uint128 amounts = _claimReward(msg.sender, receiver);
        vault.transferAllocatedTokens(msg.sender, receiver, amounts);

        emit RewardClaimed(receiver, amounts);
        return amounts;
    }

    function vaultClaimReward(address claimant, address receiver) external returns (uint256) {
        require(msg.sender == address(vault));
        uint128 amounts = _claimReward(claimant, receiver);

        emit RewardClaimed(receiver, 0);
        return amounts;
    }

    function claimableReward(address account) external view returns (uint256 vineAmount) {
        uint256 updated = periodFinish;
        if (updated > block.timestamp) updated = block.timestamp;
        uint256 duration = updated - lastUpdate;
        uint256 balance = balanceOf[account];
        uint256 supply = totalSupply;
        uint256 amounts;

        uint256 integral = rewardIntegral;
            if (supply > 0) {
                integral += (duration * rewardRate * 1e18) / supply;
            }
            uint256 integralFor = rewardIntegralFor[account];
            amounts = storedPendingReward[account] + ((balance * (integral - integralFor)) / 1e18);
        return amounts;
    }

    function approve(address _spender, uint256 _value) public returns (bool) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function _transfer(address _from, address _to, uint256 _value) internal {
        uint256 supply = totalSupply;

        uint256 balance = balanceOf[_from];
        balanceOf[_from] = balance - _value;
        _updateIntegrals(_from, balance, supply);

        balance = balanceOf[_to];
        balanceOf[_to] = balance + _value;
        _updateIntegrals(_to, balance, supply);

        emit Transfer(_from, _to, _value);
    }

    function transfer(address _to, uint256 _value) public returns (bool) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
        uint256 allowed = allowance[_from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[_from][msg.sender] = allowed - _value;
        }
        _transfer(_from, _to, _value);
        return true;
    }

    function _updateIntegrals(address account, uint256 balance, uint256 supply) internal {
        uint256 updated = periodFinish;
        if (updated > block.timestamp) updated = block.timestamp;
        uint256 duration = updated - lastUpdate;
        if (duration > 0) lastUpdate = uint32(updated);

        uint256 integral = rewardIntegral;
            if (duration > 0 && supply > 0) {
                integral += (duration * rewardRate * 1e18) / supply;
                rewardIntegral = integral;
            }
            if (account != address(0)) {
                uint256 integralFor = rewardIntegralFor[account];
                if (integral > integralFor) {
                    storedPendingReward[account] += uint128((balance * (integral - integralFor)) / 1e18);
                    rewardIntegralFor[account] = integral;
                }
            }
    }

    function pushExcessEmissions() external {
        _pushExcessEmissions(0);
    }

    function _pushExcessEmissions(uint256 newAmount) internal {
        if (vault.lockWeeks() > 0) storedExcessEmissions = uint128(storedExcessEmissions + newAmount);
        else {
            uint256 excess = storedExcessEmissions + newAmount;
            storedExcessEmissions = 0;
            vault.transferAllocatedTokens(address(this), address(this), excess);
            vault.increaseUnallocatedSupply(VINE.balanceOf(address(this)));
        }
    }

    function fetchRewards() external {
        require(block.timestamp / 1 weeks >= periodFinish / 1 weeks, "Can only fetch once per week");
        _updateIntegrals(address(0), 0, totalSupply);
        _fetchRewards();
    }

    function _fetchRewards() internal {
        uint256 vineAmount;
        uint256 id = emissionId;
        if (id > 0) vineAmount = vault.allocateNewEmissions(id);

        // apply max weekly emission limit
        uint256 maxWeekly = maxWeeklyEmissionPct;
        if (maxWeekly < 10000) {
            maxWeekly = (vault.weeklyEmissions(vault.getWeek()) * maxWeekly) / 10000;
            if (vineAmount > maxWeekly) {
                emit MaxWeeklyEmissionsExceeded(vineAmount, maxWeekly);
                _pushExcessEmissions(vineAmount - maxWeekly);
                vineAmount = maxWeekly;
            }
        }

        uint256 _periodFinish = periodFinish;
        if (block.timestamp < _periodFinish) {
            uint256 remaining = _periodFinish - block.timestamp;
            vineAmount += remaining * rewardRate;
        }
        rewardRate = uint128(vineAmount / REWARD_DURATION);

        lastUpdate = uint32(block.timestamp);
        periodFinish = uint32(block.timestamp + REWARD_DURATION);
    }
}
