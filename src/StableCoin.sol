// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IStablecoin } from "src/interfaces/IStablecoin.sol";


contract StableCoin is IStablecoin, ERC20{

    address public immutable conjurer;

    error StableCoin__onlyConjurer();

    constructor() 
    ERC20("Chad USD", "CUSD")
    {
        conjurer = msg.sender;
    }

    modifier onlyConjurer() {
        if(msg.sender != conjurer){
            revert StableCoin__onlyConjurer();
        }
        _;
    }

    function conjure(address to, uint256 amount) external override onlyConjurer {
        _mint(to, amount);
    }

    function disappear(uint256 amount) external override onlyConjurer {
        _burn(msg.sender, amount);
    }

}
