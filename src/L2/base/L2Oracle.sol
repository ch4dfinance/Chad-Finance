// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Oracle, IAggregator } from "src/Oracle.sol";

contract L2Oracle is Oracle {

    uint256 private constant GRACE_PERIOD_TIME = 3600;

    error L2Oracle__sequencerDown();
    error L2Oracle__gracePeriodNotOver();

    IAggregator public constant sequencerUptimeFeed = IAggregator(0xBCF85224fc0756B9Fa45aA7892530B47e10b6433);

    function price(address token) public override view returns(uint256 _price) {
        // check uptime rollup
        (
            /*uint80 roundID*/,
            int256 answer,
            uint256 startedAt,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = sequencerUptimeFeed.latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert L2Oracle__sequencerDown();
        }

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= GRACE_PERIOD_TIME) {
            revert L2Oracle__gracePeriodNotOver();
        }

        _price = super.price(token);
    }
}