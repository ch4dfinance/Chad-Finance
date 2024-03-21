// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IStablecoin } from 'src/interfaces/IStablecoin.sol';

struct VaultInfo {
    uint128 conjureLimit;
    uint128 totalConjured;
}

interface IConjurer {

    event Conjure(address vault, address user, uint256 amount);
    event Disappear(address vault, uint256 amount);
    event VaultAdded(address vault, uint256 conjureLimit);
    event VaultUpdated(address vault, uint256 conjureLimit);

    function conjure(address usr, uint256 amount) external;

    function disappear(uint256 amount) external;

    function vaultInfo(address vault) external view returns (VaultInfo memory);

    function addVault(address vault, uint256 conjureLimit) external;

    function changeVaultLimit(address vault, uint256 conjureLimit) external;

    function stablecoin() external view returns (IStablecoin);

}