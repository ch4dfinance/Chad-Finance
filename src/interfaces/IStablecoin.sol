// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IStablecoin is IERC20 {

    function conjurer() external view returns (address);

    function conjure(address to, uint256 amount) external;

    function disappear(uint256 amount) external;
    
}