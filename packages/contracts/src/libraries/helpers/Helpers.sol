// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {DataTypes} from "../types/DataTypes.sol";

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {IStableDebtToken} from "../../interfaces/IStableDebtToken.sol";
import {IVariableDebtToken} from "../../interfaces/IVariableDebtToken.sol";

library Helpers {
    /**
     * @dev Fetches the user current stable and variable debt balances
     * @param user The user address
     * @param reserve The reserve data object
     * @return The stable and variable debt balance
     *
     */
    function getUserCurrentDebt(address user, DataTypes.ReserveData storage reserve)
        internal
        view
        returns (uint256, uint256)
    {
        return (
            IERC20(reserve.stableDebtTokenAddress).balanceOf(user),
            IERC20(reserve.variableDebtTokenAddress).balanceOf(user)
        );
    }

    function getUserCurrentDebtMemory(address user, DataTypes.ReserveData memory reserve)
        internal
        view
        returns (uint256, uint256)
    {
        return (
            IERC20(reserve.stableDebtTokenAddress).balanceOf(user),
            IERC20(reserve.variableDebtTokenAddress).balanceOf(user)
        );
    }
}
