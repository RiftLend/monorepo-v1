// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Predeploys} from "@contracts-bedrock/libraries/Predeploys.sol";
import {SuperchainERC20} from "@contracts-bedrock/L2/SuperchainERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5/token/ERC20/utils/SafeERC20.sol";
import {SuperOwnable} from "./interop-std/SuperOwnable.sol";

import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";

/// @dev whenever user uses this with SuperchainTokenBridge, the destination chain will mint aToken (if underlying < totalBalances) and transfer underlying remaining
contract SuperchainAsset is SuperchainERC20, SuperOwnable {
    using SafeERC20 for IERC20;

    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    address public underlying; // address of underlying asset
    mapping(address user => uint256 balance) public balances; // user balance of underlying
    uint256 public totalBalances; // total balances of underlying
    ILendingPoolAddressesProvider public immutable provider;

    modifier onlyLendingPoolConfigurator() {
        require(
            provider.getLendingPoolConfigurator() == msg.sender, "Only lending pool configurator can call this function"
        );
        _;
    }

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

    /// @dev minting more than totalBalances will mint aToken and transfer underlying
    /// only callable by SuperchainTokenBridge (which has already burned the aToken amount on source chain)
    function _mint(address to_, uint256 amount_) internal override {
        if (amount_ > totalBalances) {
            // need to mint more than totalBalances
            balances[to_] += amount_ - totalBalances;
            super._mint(to_, amount_ - totalBalances);
            // reset totalBalances and transfer underlying
            totalBalances = 0;
            IERC20(underlying).safeTransfer(to_, totalBalances);
        } else {
            totalBalances -= amount_;
            IERC20(underlying).safeTransfer(to_, amount_);
        }
    }

    function mint(address to_, uint256 amount_) external {
        balances[to_] += amount_;
        totalBalances += amount_;
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount_);
        super._mint(to_, amount_);
    }

    function _burn(address from_, uint256 amount_) internal override {
        balances[from_] -= amount_;
        super._burn(from_, amount_);
    }

    function burn(address to_, uint256 amount_) external {
        totalBalances -= amount_;
        _burn(msg.sender, amount_);
        IERC20(underlying).safeTransfer(to_, amount_);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        // Call the parent contract's transfer function
        bool success = super.transfer(recipient, amount);
        if (success) {
            balances[msg.sender] -= amount;
            balances[recipient] += amount;
        }
        return success;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        // Call the parent contract's transferFrom function
        bool success = super.transferFrom(sender, recipient, amount);
        if (success) {
            balances[sender] -= amount;
            balances[recipient] += amount;
        }
        return success;
    }

    /// @dev bridge underlying to another chain using bungee api
    function bridgeUnderlying(address payable _to, bytes memory txData, address _allowanceTarget, uint256 _amount)
        external
        onlyLendingPoolConfigurator
    {
        require(_amount <= totalBalances - totalSupply(), "Amount exceeds excess balance");
        //@audit it should be totalSupply() - totalBalances, (when totalSupply() is reduced, totalBalances is also reduced)
        IERC20(underlying).approve(_allowanceTarget, _amount);
        (bool success,) = _to.call(txData);
        require(success);
    }

    /// @dev During bridging, we may receive anyTokens / hTokens if there's not enough underlying
    // therefore we may need to withdraw them and manually swap
    function withdrawTokens(address _token, address _recepient) public onlyLendingPoolConfigurator {
        require(_token != underlying, "Cannot withdraw underlying");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_recepient, amount);
    }

    /// @dev Override version function from both parent contracts
    function version() external pure override(SuperchainERC20, SuperOwnable) returns (string memory) {
        return "1.0.0";
    }
}
