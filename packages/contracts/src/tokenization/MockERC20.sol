// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts-v5/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        
    }

    function mint(address account, uint256 value) public {
        _mint(account, value);
    }
}

