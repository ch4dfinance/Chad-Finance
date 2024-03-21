// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { SafeERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { VaultInfo } from "src/interfaces/IConjurer.sol";


interface L2Bridge {
    function bridgeERC20To(
        address localToken, 
        address remoteToken, 
        address to, 
        uint256 amount, 
        uint32 minGasLimit, 
        bytes calldata extraData
    ) external;
}

contract L2Conjurer is Ownable {
    using SafeERC20 for IERC20;

    event Conjure(address vault, address user, uint256 amount);
    event Disappear(address vault, uint256 amount);
    event VaultAdded(address vault, uint256 conjureLimit);
    event VaultUpdated(address vault, uint256 conjureLimit);

    error Conjurer__vaultAlreadyAdded();
    error Conjurer__vaultNotAdded();
    error Conjurer__vaultLimitExceeded();
    error Conjurer__vaultBurnExceeded();
    error Conjurer__notEnoughTokens();

    mapping(address => VaultInfo) internal _vaultInfo;

    L2Bridge internal constant bridge = L2Bridge(0x4200000000000000000000000000000000000010);

    address public constant l1Stablecoin = 0x0b6A24A288eF6e1bFFd94EBe0EE026D80Cb4cE82;

    IERC20 public constant stablecoin = IERC20(0x3Df6a89859089715235153582f53114898bB0145);

    // Vault address on mainnet for optimism
    address public constant opVault = 0x76186f2631C9dc38171c918774C2F7f5D1a9e734;

    uint256 public totalConjured;
    uint256 public totalLimit;


    function vaultInfo(address vault) external view returns (VaultInfo memory) {
        return _vaultInfo[vault];
    }

    function addVault(address vault, uint256 conjureLimit) external onlyOwner {
        
        if(_vaultInfo[vault].conjureLimit != 0 || _vaultInfo[vault].totalConjured != 0){
            revert Conjurer__vaultAlreadyAdded();
        }

        _vaultInfo[vault].conjureLimit = uint128(conjureLimit);

        totalLimit += conjureLimit;

        // To make sure conjurer have enough tokens to serve vault limits
        if(stablecoin.balanceOf(address(this)) + totalConjured < totalLimit){
            revert Conjurer__notEnoughTokens();
        }

        emit VaultAdded(vault, conjureLimit);
    }

    function changeVaultLimit(address vault, uint256 conjureLimit) external onlyOwner {

        if(_vaultInfo[vault].conjureLimit == 0) {
            revert Conjurer__vaultNotAdded();
        }

        totalLimit = totalLimit + conjureLimit - _vaultInfo[vault].conjureLimit;

        _vaultInfo[vault].conjureLimit = uint128(conjureLimit);
        
        // To make sure conjurer have enough tokens to serve vault limits
        if(stablecoin.balanceOf(address(this)) + totalConjured < totalLimit){
            revert Conjurer__notEnoughTokens();
        }

        emit VaultUpdated(vault, conjureLimit);
    }
    
    function conjure(address usr, uint256 amount) external {
        
        if(_vaultInfo[msg.sender].totalConjured + uint128(amount) > _vaultInfo[msg.sender].conjureLimit){
            revert Conjurer__vaultLimitExceeded();
        }
        
        _vaultInfo[msg.sender].totalConjured += uint128(amount);
        
        stablecoin.safeTransfer(usr, amount);
        totalConjured += amount;
        
        emit Conjure(msg.sender, usr, amount);
    }

    function disappear(uint256 amount) external {
        
        if(_vaultInfo[msg.sender].totalConjured < uint128(amount)){
            revert Conjurer__vaultBurnExceeded();
        }

        _vaultInfo[msg.sender].totalConjured -= uint128(amount);
        
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);
        totalConjured -= amount;
        
        emit Disappear(msg.sender, amount);
    }

    function burnToMainnet(uint256 amount) external onlyOwner {
        stablecoin.safeApprove(address(bridge), amount);
        bridge.bridgeERC20To(address(stablecoin), l1Stablecoin, opVault, amount, 150_000, new bytes(0));

        // Before burning to mainnet reduce limit on base first
        // To make sure conjurer have enough tokens to serve vault limits
        if(stablecoin.balanceOf(address(this)) + totalConjured < totalLimit){
            revert Conjurer__notEnoughTokens();
        }
    } 

}
