// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IYieldModule} from "../../src/interfaces/IYieldModule.sol";

contract MockERC20 is ERC20, IYieldModule {
    uint256 public accruedYield;
    
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function mint(uint256 amount, address receiver) external override {
        _mint(receiver, amount);
    }
    
    function burn(uint256 amount, address receiver) external override {
        _burn(msg.sender, amount);
        if (receiver != address(0)) {
            _mint(receiver, amount);
        }
    }
    
    function claimYield(uint256 amount, address receiver) external override {
        require(accruedYield >= amount, "Insufficient yield");
        accruedYield -= amount;
        _mint(receiver, amount);
    }
    
    function yieldAccrued() external view override returns (uint256) {
        return accruedYield;
    }
    
    function setAccruedYield(uint256 amount) external {
        accruedYield = amount;
    }
}