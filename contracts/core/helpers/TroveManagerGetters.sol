// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "../../interfaces/ITroveManager.sol";
import "../../interfaces/IFactory.sol";
import "../../dependencies/VineSignature.sol";


/*  Helper contract for grabbing Trove data for the front end. Not part of the core Vine system. */
contract TroveManagerGetters is VineSignature {
    struct Collateral {
        address collateral;
        address[] troveManagers;
    }

    IFactory public immutable factory;

    constructor(IFactory _factory) {
        factory = _factory;
    }

    /**
        @notice Returns all active system trove managers and collaterals, as an
        `       array of tuples of [(collateral, [troveManager, ...]), ...]
     */
    function getAllCollateralsAndTroveManagers() external view returns (Collateral[] memory) {
        uint256 length = factory.troveManagerCount();
        address[2][] memory troveManagersAndCollaterals = new address[2][](length);
        address[] memory uniqueCollaterals = new address[](length);
        uint256 collateralCount;
        for (uint i = 0; i < length; i++) {
            address troveManager = factory.troveManagers(i);
            address collateral = ITroveManager(troveManager).collateralToken();
            troveManagersAndCollaterals[i] = [troveManager, collateral];
            for (uint x = 0; x < length; x++) {
                if (uniqueCollaterals[x] == collateral) break;
                if (uniqueCollaterals[x] == address(0)) {
                    uniqueCollaterals[x] = collateral;
                    collateralCount++;
                    break;
                }
            }
        }
        Collateral[] memory collateralMap = new Collateral[](collateralCount);
        for (uint i = 0; i < collateralCount; i++) {
            collateralMap[i].collateral = uniqueCollaterals[i];
            uint tmCollCount = 0;
            address[] memory troveManagers = new address[](length);
            for (uint x = 0; x < length; x++) {
                if (troveManagersAndCollaterals[x][1] == uniqueCollaterals[i]) {
                    troveManagers[tmCollCount] = troveManagersAndCollaterals[x][0];
                    tmCollCount++;
                }
            }
            collateralMap[i].troveManagers = new address[](tmCollCount);
            for (uint x = 0; x < tmCollCount; x++) {
                collateralMap[i].troveManagers[x] = troveManagers[x];
            }
        }

        return collateralMap;
    }

    /**
        @notice Returns a list of trove managers where `account` has an existing trove
     */
    function getActiveTroveManagersForAccount(address account) external view returns (address[] memory) {
        uint256 length = factory.troveManagerCount();
        address[] memory troveManagers = new address[](length);
        uint256 tmCount;
        for (uint i = 0; i < length; i++) {
            address troveManager = factory.troveManagers(i);
            if (ITroveManager(troveManager).getTroveStatus(account) > 0) {
                troveManagers[tmCount] = troveManager;
                tmCount++;
            }
        }
        assembly {
            mstore(troveManagers, tmCount)
        }
        return troveManagers;
    }

    function getTrove(SignIn calldata auth, address _troveManager) external authenticated(auth) view returns (
            uint256 debt,
            uint256 coll,
            uint256 stake,
            uint8 status,
            uint128 arrayIndex,
            uint256 activeInterestIndex
        ) {
        return ITroveManager(_troveManager).getTrove(auth.user);
    }

    function getTroveStatus(SignIn calldata auth, address _troveManager) external authenticated(auth) view returns (uint256) {
        return ITroveManager(_troveManager).getTroveStatus(auth.user);
    }

    function getTroveStake(SignIn calldata auth, address _troveManager) external authenticated(auth) view returns (uint256) {
        return ITroveManager(_troveManager).getTroveStake(auth.user);
    }

    /**
        @notice Get the current total collateral and debt amounts for a trove
        @dev Also includes pending rewards from redistribution
     */
    function getTroveCollAndDebt(SignIn calldata auth, address _troveManager) public authenticated(auth) view returns (uint256 coll, uint256 debt) {
        return ITroveManager(_troveManager).getTroveCollAndDebt(auth.user);
    }

    function getEntireDebtAndColl(
        SignIn calldata auth, address _troveManager
    ) public authenticated(auth) view returns (uint256 debt, uint256 coll, uint256 pendingDebtReward, uint256 pendingCollateralReward) {
        return ITroveManager(_troveManager).getEntireDebtAndColl(auth.user);
    }

    function getNominalICR(SignIn calldata auth, address _troveManager) public authenticated(auth) view returns (uint256) {
        return ITroveManager(_troveManager).getNominalICR(auth.user);
    }

    function getPendingCollAndDebtRewards(SignIn calldata auth, address _troveManager) public authenticated(auth) view returns (uint256, uint256) {
        return ITroveManager(_troveManager).getPendingCollAndDebtRewards(auth.user);
    }
}
