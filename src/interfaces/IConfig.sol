// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

struct TokenInfo {
    uint16 collateralFactor;
    uint8 decimals;
}

interface IConfig {

    function setOracle(address _oracle) external;

    function setTreasury(address _treasury) external;

    function setCollateralFactor(address _asset, uint256 _collateralFactor, uint8 _decimals) external;

    function tokenInfos(address _asset) external view returns (TokenInfo memory);

    function oracle() external view returns (address);

    function treasury() external view returns (address);

    function conjurer() external view returns (address);

    function stablecoin() external view returns (address);

    function BASIS_POINT() external view returns (uint256);
}   