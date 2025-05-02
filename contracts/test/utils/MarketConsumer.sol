// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {FutarchyFactory} from "../../src/FutarchyFactory.sol";
import {FutarchyProposal} from "../../src/FutarchyProposal.sol";

contract MarketConsumer {
    FutarchyFactory public factory;

    /// @dev Emitted once per market when we “process” it.
    event Processed(address indexed market);

    constructor(address _factory) {
        factory = FutarchyFactory(_factory);
    }

    /// @notice Naïvely pull the whole array in one shot.
    /// ‣ WILL revert if `proposals.length` is so large that `allMarkets()` runs out of gas.
    function process(uint256 index) external {
        address[] memory mkts = factory.allMarkets();
        address m = mkts[index];
            emit Processed(m);
        
    }
}