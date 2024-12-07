// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts-v5/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    uint8 decimals_;
    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) {
        decimals_ = _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return decimals_;
    }

    receive() external payable {}

    fallback() external payable {}
}
