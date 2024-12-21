// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Predeploys} from "@contracts-bedrock/libraries/Predeploys.sol";
import {SuperchainERC20} from "@contracts-bedrock/L2/SuperchainERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {SuperOwnable} from "@interop-std/auth/SuperOwnable.sol";

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";

/// @dev whenever user uses this with SuperchainTokenBridge, the destination chain will mint aToken (if underlying < totalBalances) and transfer underlying remaining
contract SuperAsset is SuperchainERC20 {
    using SafeERC20 for IERC20;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address underlying_,
        ILendingPoolAddressesProvider provider_,
        address admin_
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        underlying = underlying_;
        provider = provider_;
        _initializeSuperOwner(uint64(block.chainid), admin_);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
