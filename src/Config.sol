// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IERC20Metadata } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { IStablecoin } from "src/interfaces/IStablecoin.sol";
import { IConfig, TokenInfo } from "src/interfaces/IConfig.sol";

contract Config is Ownable, IConfig {

    error Config__invalidValue();

    mapping (address => TokenInfo) internal _tokenInfos;

    address public oracle;

    address public treasury;

    address public immutable conjurer;

    address public immutable stablecoin;

    uint256 public constant BASIS_POINT = 10_000;

    constructor(address _stablecoin) {
        stablecoin = _stablecoin;
        conjurer = IStablecoin(_stablecoin).conjurer();
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function tokenInfos(address _asset) external override view returns (TokenInfo memory tokenInfo){
        tokenInfo = _tokenInfos[_asset];
    }

    function setCollateralFactor(address _asset, uint256 _collateralFactor, uint8 _decimals) external onlyOwner {
        if(_collateralFactor >= BASIS_POINT || _asset == address(0) || _decimals > 18){
            revert Config__invalidValue();
        }
        
        TokenInfo storage tokenInfo = _tokenInfos[_asset];

        try IERC20Metadata(_asset).decimals() returns (uint8 decimals){
                tokenInfo.decimals = decimals;
        }
        catch{
            tokenInfo.decimals = _decimals;
        }

        tokenInfo.collateralFactor = uint16(_collateralFactor);
    }
}