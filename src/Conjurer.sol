// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { VaultInfo, IConjurer } from "src/interfaces/IConjurer.sol";
import { StableCoin, IStablecoin } from "src/StableCoin.sol";


contract Conjurer is IConjurer, Ownable {


    error Conjurer__vaultAlreadyAdded();
    error Conjurer__vaultNotAdded();
    error Conjurer__vaultLimitExceeded();
    error Conjurer__vaultBurnExceeded();

    mapping(address => VaultInfo) internal _vaultInfo;

    IStablecoin public immutable stablecoin;

    uint256 public totalConjured;

    constructor() {
        stablecoin = IStablecoin(new StableCoin());
    }

    function vaultInfo(address vault) external override view returns (VaultInfo memory) {
        return _vaultInfo[vault];
    }

    function addVault(address vault, uint256 conjureLimit) external onlyOwner override {
        
        if(_vaultInfo[vault].conjureLimit != 0 || _vaultInfo[vault].totalConjured != 0){
            revert Conjurer__vaultAlreadyAdded();
        }

        _vaultInfo[vault].conjureLimit = uint128(conjureLimit);

        emit VaultAdded(vault, conjureLimit);
    }

    function changeVaultLimit(address vault, uint256 conjureLimit) external onlyOwner override {

        if(_vaultInfo[vault].conjureLimit == 0) {
            revert Conjurer__vaultNotAdded();
        }
        
        _vaultInfo[vault].conjureLimit = uint128(conjureLimit);
        
        emit VaultUpdated(vault, conjureLimit);
    }
    
    function conjure(address usr, uint256 amount) external override {
        
        if(_vaultInfo[msg.sender].totalConjured + uint128(amount) > _vaultInfo[msg.sender].conjureLimit){
            revert Conjurer__vaultLimitExceeded();
        }
        
        _vaultInfo[msg.sender].totalConjured += uint128(amount);
        
        stablecoin.conjure(usr, amount);
        totalConjured += amount;
        
        emit Conjure(msg.sender, usr, amount);
    }

    function disappear(uint256 amount) external override {
        
        if(_vaultInfo[msg.sender].totalConjured < uint128(amount)){
            revert Conjurer__vaultBurnExceeded();
        }

        _vaultInfo[msg.sender].totalConjured -= uint128(amount);
        
        stablecoin.disappear(amount);
        totalConjured -= amount;
        
        emit Disappear(msg.sender, amount);
    }

}
