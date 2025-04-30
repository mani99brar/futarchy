// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "../../src/Interfaces.sol";
/// @dev Minimal IERC20 implementation to serve as a fake wrapper in exploit tests.
contract FakeERC20 is IERC20 {
    string public override symbol;
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    uint256 private totalSupply_;

    constructor() {
        symbol ="FAKE";
    }

    function totalSupply() external view override returns (uint256) {
        return totalSupply_;
    }

    function balanceOf(address owner) external view override returns (uint256) {
        return balances[owner];
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(allowances[from][msg.sender] >= amount, "FakeERC20: allowance exceeded");
        allowances[from][msg.sender] -= amount;
        require(balances[from] >= amount, "FakeERC20: insufficient balance");
        balances[from] -= amount;
        balances[to] += amount;
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balances[msg.sender] >= amount, "FakeERC20: insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    /// @notice Mints new tokens to `to`. Only for testing.
    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        totalSupply_ += amount;
    }
}