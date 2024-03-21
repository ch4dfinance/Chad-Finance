// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IConjurer } from "src/interfaces/IConjurer.sol";

interface L1Bridge {
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}

contract OpVault is Ownable {

    L1Bridge internal constant bridge = L1Bridge(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1);

    IConjurer internal constant conjurer = IConjurer(0x27f9ec56F91e9851443417D307E538e919E47219);

    IERC20 internal constant stablecoin = IERC20(0x0b6A24A288eF6e1bFFd94EBe0EE026D80Cb4cE82);

    address internal constant l2coin = 0x3Df6a89859089715235153582f53114898bB0145;

    // mint and bridge those tokens to Base L2
    function conjure(address to, uint256 amount) external onlyOwner {

        conjurer.conjure(address(this), amount);

        stablecoin.approve(address(bridge), amount);

        bridge.bridgeERC20To(address(stablecoin), l2coin, to, amount, 150_000, new bytes(0));
    }

    // burn tokens received from bridge
    function disappear(uint256 amount) external onlyOwner {
        stablecoin.transfer(address(conjurer), amount);
        conjurer.disappear(amount);
    }

}