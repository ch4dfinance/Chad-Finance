// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { SafeERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import { SafeCast } from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { INonfungiblePositionManager } from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import { LiquidityAmounts } from "v3-periphery/libraries/LiquidityAmounts.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { IConfig, TokenInfo } from "src/interfaces/IConfig.sol";
import { IConjurer } from "src/interfaces/IConjurer.sol";
import { IOracle } from "src/interfaces/IOracle.sol";


contract L2Vault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeCast for uint256;

    struct Debt {
        uint128 debtAmount;
        uint32 timestamp;
        uint96 interestAccrued;
    }

    event Borrow(address indexed user, uint256 indexed tokenId, uint256 amount);
    event Repay(address indexed user, uint256 indexed tokenId, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed tokenId);
    event Liquidate(address indexed liquidator, uint256 indexed tokenId, uint256 amount);

    error Vault__zeroAddress();
    error Vault__positionUnderwater();
    error Vault__invalidPosition();
    error Vault__invalidPositionAccess();
    error Vault__selfLiquidationNotAllowed();
    error Vault__positionNotLiquidatable();
    error Vault__positionDebtNotZero();
    error Vault__failedToAddNFTPosition();
    error Vault__failedToRemoveNFTPosition();

    uint256 internal constant ONE = 1e18;
    uint256 internal constant LIQUIDATION_BONUS = 1000;
    uint256 internal constant BASIS_POINT = 10_000;

    IConjurer public immutable conjurer;
    IERC20 public immutable stablecoin;
    INonfungiblePositionManager public immutable positionManager;

    IConfig public immutable config;
    IOracle public immutable oracle;
    
    mapping (address => EnumerableSet.UintSet) private _ownerTokens;

    mapping (uint256 => address) public nftOwner;
    mapping (uint256 => Debt) private debts;

    uint256 internal constant interestPerSecond = 1268391679; // 4 % per year linear interest

    constructor(address _positionManager, address _config) {
        if(_positionManager == address(0) || _config == address(0)){
            revert Vault__zeroAddress();
        }
        positionManager = INonfungiblePositionManager(_positionManager);
        config = IConfig(_config);
        conjurer = IConjurer(config.conjurer());
        stablecoin = IERC20(config.stablecoin());
        oracle = IOracle(config.oracle());
    }

    function ownerTokens(address owner) external view returns (uint256[] memory tokens){
        tokens = _ownerTokens[owner].values();
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        return _ownerTokens[owner].length();
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual returns (uint256) {
        return _ownerTokens[owner].at(index);
    }

    function borrow(uint256 pos, uint256 amount) external {

        _checkOwnerAndtransferNFT(pos);
        _accrueInterest(pos);
        _addDebt(pos, amount);

        conjurer.conjure(msg.sender, amount);

        if(!checkPositionHealth(pos)){
            revert Vault__positionUnderwater();
        }

        emit Borrow(msg.sender, pos, amount);
    }

    function _accrueInterest(uint256 pos) internal {
        Debt storage debt = debts[pos];
        uint256 interestAccrued = Math.mulDiv(debt.debtAmount, interestPerSecond * (block.timestamp - debt.timestamp), ONE, Math.Rounding.Up);
        debt.interestAccrued = debt.interestAccrued + interestAccrued.toUint96();
        debt.timestamp = block.timestamp.toUint32();
    }

    function _subInterest(uint256 pos, uint256 amount) internal {
        Debt storage debt = debts[pos];
        debt.interestAccrued = debt.interestAccrued - amount.toUint96();
    }

    function _addDebt(uint256 pos, uint256 amount) internal {
        Debt storage debt = debts[pos];
        debt.debtAmount = debt.debtAmount + amount.toUint128();
    }

    function _subDebt(uint256 pos, uint256 amount) internal {
        Debt storage debt = debts[pos];
        debt.debtAmount = debt.debtAmount - amount.toUint128();
    }

    function _getDebtAndInterest (uint256 pos) internal view returns (uint256 totalDebt, uint256 interestAccrued){
        Debt memory debt = debts[pos];
        interestAccrued = Math.mulDiv(debt.debtAmount, interestPerSecond * (block.timestamp - debt.timestamp), ONE, Math.Rounding.Up);
        interestAccrued = debt.interestAccrued + interestAccrued; 
        totalDebt = debt.debtAmount + interestAccrued;
    }

    function getDebtInfo (uint256 pos) public view returns (uint256 totalDebt, uint256 interestAccrued, uint256 max) {
        (totalDebt, interestAccrued) = _getDebtAndInterest(pos);
        max = maxDebt(pos);
    }

    function checkPositionHealth (uint256 pos) public view returns (bool) {

        (uint256 totalDebt,, uint256 max) = getDebtInfo(pos);

        return max >= totalDebt;
    }

    function _checkOwnerAndtransferNFT(uint256 pos) internal {
        // check if NFT is already transferred into vault
        if(nftOwner[pos] == msg.sender){
            return;
        }
        // transfer it and mark owner for the NFT
        positionManager.transferFrom(msg.sender, address(this), pos);
        nftOwner[pos] = msg.sender;
        if(!_ownerTokens[msg.sender].add(pos)){
            revert Vault__failedToAddNFTPosition();
        }
    }

    /**
        @notice Repay debt for nft position
        @param pos position id of Uniswap V3 NFT
     */
    function repay(uint256 pos, uint256 amount) external {
        if(nftOwner[pos] == address(0)){
            revert Vault__invalidPosition();
        }
        _accrueInterest(pos);

        (uint256 totalDebt, uint256 interest) = _getDebtAndInterest(pos);

        if(amount > totalDebt){
            amount = totalDebt;
        }

        stablecoin.transferFrom(msg.sender, address(this), amount);

        if(amount <= interest) {
            // first reduce interest
            stablecoin.transfer(config.treasury(), amount);
            _subInterest(pos, amount);
            amount = 0;
        }else{

            stablecoin.transfer(config.treasury(), interest);
            _subInterest(pos, interest);
            amount = amount - interest;
            
            // L2 conjurer transfer from since there is no burn
            stablecoin.approve(address(conjurer), amount);
            conjurer.disappear(amount);
            _subDebt(pos, amount);
        }

        emit Repay(msg.sender, pos, amount);
    }

    /**
        @notice Withdraw NFT from vault, can only be done when there is no debt
        @param pos position id of Uniswap V3 NFT
     */
    function withdraw(uint256 pos) external {
        if(nftOwner[pos] != msg.sender){
            revert Vault__invalidPositionAccess();
        }

        _accrueInterest(pos);
        (uint256 debt, ) = _getDebtAndInterest(pos);

        if(debt != 0){
            revert Vault__positionDebtNotZero();
        }

        delete debts[pos];
        delete nftOwner[pos];
        if(!_ownerTokens[msg.sender].remove(pos)){
            revert Vault__failedToRemoveNFTPosition();
        }

        positionManager.transferFrom(address(this), msg.sender, pos);

        emit Withdraw(msg.sender, pos);
    }

    /**
        @notice Liquidate debt position in vault, can only be done when position is unhealthy
        @param pos position id of Uniswap V3 NFT
     */
    function liquidate(uint256 pos) external {
        if(nftOwner[pos] == address(0)){
            revert Vault__invalidPosition();
        }

        if(nftOwner[pos] == msg.sender){
            revert Vault__selfLiquidationNotAllowed();
        }

        _accrueInterest(pos);

        if(checkPositionHealth(pos)){
            revert Vault__positionNotLiquidatable();
        }

        Debt memory debt = debts[pos];

        uint256 repayAmount = debt.debtAmount + debt.interestAccrued;

        stablecoin.transferFrom(msg.sender, address(this), repayAmount);

        stablecoin.transfer(config.treasury(), debt.interestAccrued);
        stablecoin.approve(address(conjurer), debt.debtAmount);

        conjurer.disappear(debt.debtAmount);

        delete debts[pos];

        if(!_ownerTokens[nftOwner[pos]].remove(pos)){
            revert Vault__failedToRemoveNFTPosition();
        }

        address posOwner = nftOwner[pos];

        delete nftOwner[pos];

        _payLiquidator(posOwner, repayAmount, pos);

        emit Liquidate(msg.sender, pos, repayAmount);
    }

    /**
        @notice Claim fees accrued on Uniswap V3
        @param pos position id of Uniswap V3 NFT
     */
    function claimFees(uint256 pos) external {

        _accrueInterest(pos);

        INonfungiblePositionManager.CollectParams memory collect = INonfungiblePositionManager
            .CollectParams({
                tokenId: pos,
                recipient: nftOwner[pos],
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        positionManager.collect(collect);

        if(!checkPositionHealth(pos)){
            revert Vault__positionUnderwater();
        }
    }

    function _payLiquidator(address posOwner, uint256 repayAmount, uint256 pos) internal {
        (address token0, address token1, uint128 liquidity) = getPositionInfo(pos);
        (uint256 amount0, uint256 amount1) = _unwindLiquidity(pos, liquidity);

        TokenInfo memory token0Info = config.tokenInfos(token0);
        TokenInfo memory token1Info = config.tokenInfos(token1);

        uint256 nftValue = _calculatePrice(
            amount0, 
            amount1, 
            uint256(token0Info.decimals), 
            uint256(token1Info.decimals), 
            token0, 
            token1
        );

        if(Math.mulDiv(repayAmount, BASIS_POINT + LIQUIDATION_BONUS, BASIS_POINT) >= nftValue){
            // if value of nft is less than collateral expected, transfer full position to sender
            IERC20(token0).safeTransfer(msg.sender, amount0);
            IERC20(token1).safeTransfer(msg.sender, amount1);
        }else{

            uint256 ratio = Math.mulDiv(repayAmount, BASIS_POINT + LIQUIDATION_BONUS, nftValue);

            if(amount0 > 0){
                uint256 amountToTransfer = Math.mulDiv(amount0, ratio, BASIS_POINT, Math.Rounding.Up);
                // pay to liquidator
                IERC20(token0).safeTransfer(msg.sender, amountToTransfer);
                // pay to nft owner remaining funds from his position
                IERC20(token0).safeTransfer(posOwner, amount0 - amountToTransfer);
            }

            if(amount1 > 0){
                uint256 amountToTransfer = Math.mulDiv(amount1, ratio, BASIS_POINT, Math.Rounding.Up);

                IERC20(token1).safeTransfer(msg.sender, amountToTransfer);
                IERC20(token1).safeTransfer(posOwner, amount1 - amountToTransfer);
            }
        }
    }

    function _unwindLiquidity(uint256 tokenId, uint128 liquidity) internal returns (uint256 amount0, uint256 amount1) {
        
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidity = INonfungiblePositionManager
        .DecreaseLiquidityParams({
            tokenId:    tokenId,
            liquidity:  liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline:   block.timestamp
        });

        positionManager.decreaseLiquidity(decreaseLiquidity);

        INonfungiblePositionManager.CollectParams memory collect = INonfungiblePositionManager
        .CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = positionManager.collect(collect);
        positionManager.burn(tokenId);
    }

    function maxDebt(uint256 tokenId) public view returns (uint256){
        (
            address token0, 
            address token1, 
            uint256 amount0, 
            uint256 amount1, 
            TokenInfo memory token0Info,
            TokenInfo memory token1Info
        ) = _getTokenAndAmounts(tokenId);


        uint256 coll = Math.min(token0Info.collateralFactor, token1Info.collateralFactor);

        if(coll == 0){
            return 0;
        }

        return Math.mulDiv(
            coll, 
            _calculatePrice(
                amount0, 
                amount1, 
                uint256(token0Info.decimals), 
                uint256(token1Info.decimals), 
                token0, 
                token1
            ), 
            BASIS_POINT);
    }

    function getNFTValue(uint256 tokenId) public view returns (uint) {
        (address token0, address token1, uint256 amount0, uint256 amount1, 
            TokenInfo memory token0Info,
            TokenInfo memory token1Info
        ) = _getTokenAndAmounts(tokenId);


        return _calculatePrice(
            amount0, 
            amount1, 
            uint256(token0Info.decimals), 
            uint256(token1Info.decimals),
            token0, 
            token1
        );        
    }

    function getPositionInfo(uint256 tokenId) public view returns (address token0, address token1, uint128 liquidity) {
        (,,token0,token1,,,,liquidity,,,,) = positionManager.positions(tokenId);        
    }

    function _getPrices(address tokenA, address tokenB, uint8 decimalsA, uint8 decimalsB) internal view returns (uint256 priceA, uint256 priceB) {
        uint256 _priceA = IOracle(config.oracle()).price(tokenA);
        uint256 _priceB = IOracle(config.oracle()).price(tokenB);
        priceA = 10**decimalsA;
        priceB = Math.mulDiv(_priceA, 10**decimalsB, _priceB);
    }

    function _getTokenAndAmounts(uint256 tokenId) internal view returns (
        address token0, 
        address token1, 
        uint256 amount0, 
        uint256 amount1,
        TokenInfo memory token0Info,
        TokenInfo memory token1Info
    ) {

        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;

        (,,
        token0, 
        token1,,
        tickLower, 
        tickUpper, 
        liquidity,,,
        ,
        ) = positionManager.positions(tokenId);

        token0Info = config.tokenInfos(token0);
        token1Info = config.tokenInfos(token1);

        
        (uint256 price0, uint256 price1) = _getPrices(token0, token1, token0Info.decimals, token1Info.decimals);

        uint160 sqrtPriceX96 = _getSqrtPriceX96(price1, price0).toUint160();

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );
        
    }


    function _getSqrtPriceX96(uint256 priceA, uint256 priceB) internal pure returns (uint256) {
        uint256 ratioX192 = (priceA << 192)/priceB;
        return Math.sqrt(ratioX192);
    }

    function _getTick(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    function _calculatePrice(uint256 amountA, uint256 amountB, uint256 decimalA, uint256 decimalB, address tokenA, address tokenB) internal view returns (uint256 price) {
        
        uint256 priceA = oracle.price(tokenA);
        uint256 priceB = oracle.price(tokenB);
        
        price = (amountA*priceA)/(10 ** decimalA)
                + (amountB*priceB)/(10 ** decimalB);
    }

}