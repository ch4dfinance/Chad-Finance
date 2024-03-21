// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { SafeERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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

// Collect fees as interest from all vaults and then transfer it to mainnet
contract L2FeeCollector {
    using SafeERC20 for IERC20;

    L2Bridge internal constant bridge = L2Bridge(0x4200000000000000000000000000000000000010);

    IERC20 public constant stablecoin = IERC20(0x4493faE71502871245B7049580b3195bC930e661);

    // Timelock address on mainnet
    address public constant chadDao = 0x9D603A45321a3aDbFcAD0E49Fd944Cc281Baa833;
    address public constant l1Stablecoin = 0x0b6A24A288eF6e1bFFd94EBe0EE026D80Cb4cE82;

    function transferFees() external {
        uint256 balance = stablecoin.balanceOf(address(this));
        stablecoin.safeApprove(address(bridge), balance);
        bridge.bridgeERC20To(address(stablecoin), l1Stablecoin, chadDao, balance, 150_000, new bytes(0));
    }

}
