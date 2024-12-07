// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Predeploys} from "@contracts-bedrock/libraries/Predeploys.sol";
import {SuperchainERC20} from "@contracts-bedrock/L2/SuperchainERC20.sol";
import {Ownable} from "@solady/auth/Ownable.sol";

/**
 * @title L2NativeSuperchainERC20
 * @notice A custom ERC-20 token implementation for Layer 2 (L2) within a Superchain framework.
 * @dev Extends the `SuperchainERC20` contract and incorporates ownership controls via `Ownable`.
 *      This contract allows the owner to mint tokens and customize metadata.
 */
contract L2NativeSuperchainERC20 is SuperchainERC20, Ownable {
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;

    /**
     * @notice Initializes the contract with the specified parameters.
     * @dev Sets the token name, symbol, decimals, and assigns ownership to `owner_`.
     * @param owner_ The address to be set as the owner of the contract.
     * @param name_ The name of the token (e.g., "Super Token").
     * @param symbol_ The symbol of the token (e.g., "SUPER").
     * @param decimals_ The number of decimal places the token uses (e.g., 18).
     */
    constructor(address owner_, string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;

        _initializeOwner(owner_);
    }

    /**
     * @notice Retrieves the name of the token.
     * @return The name of the token as a string.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @notice Retrieves the symbol of the token.
     * @return The symbol of the token as a string.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Retrieves the number of decimals used by the token.
     * @return The number of decimals as an unsigned integer.
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mints new tokens to the specified address.
     * @dev Only callable by the owner of the contract.
     * @param to_ The address to receive the minted tokens.
     * @param amount_ The amount of tokens to mint.
     */
    function mintTo(address to_, uint256 amount_) external onlyOwner {
        _mint(to_, amount_);
    }
}
