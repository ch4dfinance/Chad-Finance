// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IERC20Metadata } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { IStablecoin } from "src/interfaces/IStablecoin.sol";
import { IConfig, TokenInfo } from "src/interfaces/IConfig.sol";

contract L2Config is Ownable, IConfig {

    error Config__invalidValue();

    mapping (address => TokenInfo) internal _tokenInfos;

    address public oracle;

    address public treasury;

    address public constant conjurer = 0xA8Eea1eAe8f7483F7aD0555783A18F730Da1AffD;

    address public constant stablecoin = 0x4493faE71502871245B7049580b3195bC930e661;

    uint256 public constant BASIS_POINT = 10_000;

    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function tokenInfos(address _asset) external override view returns (TokenInfo memory tokenInfo){
        tokenInfo = _tokenInfos[_asset];
    }

    function setCollateralFactor(address _asset, uint256 _collateralFactor, uint8) external onlyOwner {
        if(_collateralFactor >= BASIS_POINT || _asset == address(0)){
            revert Config__invalidValue();
        }
        
        TokenInfo storage tokenInfo = _tokenInfos[_asset];

        tokenInfo.decimals = IERC20Metadata(_asset).decimals();

        tokenInfo.collateralFactor = uint16(_collateralFactor);
    }
}