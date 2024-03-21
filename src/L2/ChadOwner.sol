// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface L2CrossDomainMessageSender {
    function xDomainMessageSender() external view returns (address);
}

// OP stack chains Gateway to manager contracts on behalf of timelock on L1
contract ChadOwner {

    error ChadOwner__invalidSender();
    error ChadOwner__onlyOwnerCanCrossCall();
    error ChadOwner__callFailed(bytes reason);

    event CallSuccess(address indexed target, bytes data, uint256 value);
    event OwnerChange(address newOwner);

    L2CrossDomainMessageSender internal constant crossDomainSender = L2CrossDomainMessageSender(0x4200000000000000000000000000000000000007);

    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    // to receive eth
    receive() external payable { }

    function relayMessage(address target, uint256 value, bytes calldata data) external payable {
        if(msg.sender != address(crossDomainSender)){
            revert ChadOwner__invalidSender();
        }

        if(crossDomainSender.xDomainMessageSender() != owner){
            revert ChadOwner__onlyOwnerCanCrossCall();
        }

        (bool success, bytes memory reason) = target.call{value: value}(data);

        if(!success){
            revert ChadOwner__callFailed(reason);
        }
        emit CallSuccess(target, data, value);
    }

    function transferOwner(address newOwner) external {
        if(msg.sender != address(crossDomainSender)){
            revert ChadOwner__invalidSender();
        }

        if(crossDomainSender.xDomainMessageSender() != owner){
            revert ChadOwner__onlyOwnerCanCrossCall();
        }

        owner = newOwner;
        emit OwnerChange(newOwner);
    }

}