// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { IOracle } from "src/interfaces/IOracle.sol";


interface IAggregator {
    function latestRoundData() external view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );    
    function decimals() external view returns (uint8);
}

interface IAlternateFeed {
    function price(address token) external view returns (uint256);
}

struct ChainlinkFeedInfo {
    IAggregator aggregator;
    uint96 stalenessCheck;
}

contract Oracle is IOracle, Ownable {
    // Chainlink aggregator feeds mapping for token prices in USD
    mapping(address => ChainlinkFeedInfo) internal chainkLinkFeeds;
    // Alternate aggregator feeds mapping for token prices in USD
    mapping(address => IAlternateFeed) internal alternateFeeds;

    error Oracle__tokenFeedNotPresent();
    error Oracle__priceFeedStale();

    uint256 public constant DECIMALS = 18;

    function setChainlinkSource(address token, address aggregator, uint96 stalenessCheck) external onlyOwner  {
        chainkLinkFeeds[token] = ChainlinkFeedInfo(IAggregator(aggregator), stalenessCheck);
    }

    function setAlternateSource(address token, address source) external onlyOwner {
        alternateFeeds[token] = IAlternateFeed(source);
    }

    // Get all prices in USD in 18 decimals
    function price(address token) public view virtual override  returns(uint256 _price) {

        if(address(chainkLinkFeeds[token].aggregator) != address(0)){
            int256 answer; uint256 lastUpdatedAt;

            ChainlinkFeedInfo memory feedInfo = chainkLinkFeeds[token];

            (, answer,, lastUpdatedAt,) = feedInfo.aggregator.latestRoundData();

            if(block.timestamp - lastUpdatedAt > feedInfo.stalenessCheck){
                revert Oracle__priceFeedStale();
            }

            _price = uint256(answer) * (10 ** (DECIMALS - (uint256(feedInfo.aggregator.decimals()))));

        }else if(address(alternateFeeds[token]) != address(0)){
            
            _price = alternateFeeds[token].price(token);

        }else {

            revert Oracle__tokenFeedNotPresent();

        }

    }

}

