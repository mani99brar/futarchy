// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../src/FutarchyFactory.sol";
import "../../src/FutarchyProposal.sol";
import "../../src/FutarchyRealityProxy.sol";
import "../../src/FutarchyRouter.sol";
import "../../src/Market.sol";
import {IMarketFactory, MarketView} from "../../src/MarketView.sol";
import "forge-std/Test.sol";
import "./FakeERC20.sol";

/// @dev Malicious stub that mirrors a real FutarchyProposal but returns a fake wrapper address.
contract MaliciousProposal {
    FutarchyProposal public real;
    FakeERC20 public fake;

    constructor(FutarchyProposal _real, FakeERC20 _fake) {
        real = _real;
        fake = _fake;
    }

    // Mirror collateral tokens
    function collateralToken1() external view returns (IERC20) {
        return real.collateralToken1();
    }
    function collateralToken2() external view returns (IERC20) {
        return real.collateralToken2();
    }

    // Mirror condition and collection
    function conditionId() external view returns (bytes32) {
        return real.conditionId();
    }
    function parentCollectionId() external view returns (bytes32) {
        return real.parentCollectionId();
    }

    // Return fake wrapper but real `data` so unwrap burns the genuine proxy
    function wrappedOutcome(uint256 index) external view returns (IERC20, bytes memory) {
        (, bytes memory data) = real.wrappedOutcome(index);
        return (IERC20(address(fake)), data);
    }

    function parentWrappedOutcome() external view returns (IERC20, bytes memory) {
        (, bytes memory data) = real.parentWrappedOutcome();
        return (IERC20(address(fake)), data);
    }

    // Mirror other getters
    function numOutcomes() external view returns (uint256) {
        return real.numOutcomes();
    }
    function marketName() external view returns (string memory) {
        return real.marketName();
    }
    function questionId() external view returns (bytes32) {
        return real.questionId();
    }
}

