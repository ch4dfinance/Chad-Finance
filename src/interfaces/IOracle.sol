// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IOracle {
    function price(address token) external view returns (uint256);
}