// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ICrossChainCaller} from "../src/ICrossChainCaller.sol";
import {SharedBridge} from "../src/SharedBridge.sol";
import {BridgeL2} from "../src/BridgeL2.sol";
import {ISharedBridge} from "../src/ISharedBridge.sol";
import {IBridgeL2} from "../src/IBridgeL2.sol";

contract SharedBridgeMock is SharedBridge {
    constructor(address sequencer, uint256 chainId) SharedBridge(sequencer, chainId) {}

    function editLockedEth(uint256 chainId, uint256 amount) external {
        deposits[chainId][ETH_TOKEN][ETH_TOKEN] += amount;
    }
}

contract DepositTester is Test {
    SharedBridgeMock public mainnet;
    BridgeL2 public rollup;
    uint256 public mainnetId = 1;
    uint256 public rollupId = 2;
    address public sequencer = makeAddr("sequencer");

    function setUp() public {
        mainnet = new SharedBridgeMock(sequencer, mainnetId);
        rollup = new BridgeL2(address(mainnet), rollupId, sequencer);

        vm.prank(sequencer);
        mainnet.editSupportedChain(rollupId, true);

        vm.prank(sequencer);
        rollup.editSupportedChain(mainnetId, true);

        vm.prank(sequencer);
        mainnet.setL2BridgeAddress(rollupId, address(rollup));

        // Give the rollup some ETH to mint
        vm.deal(address(rollup), 100 ether);
    }

    function test_l1ToL2_deposit() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        uint256 nonce = 0;
        vm.deal(alice, 100 ether);
        uint256[] memory chainIds = new uint256[](1);
        bytes[] memory results = new bytes[](1);
        bytes32[] memory resultHashes = new bytes32[](1);

        // Prepopulate the L1 result inbox with mintETH() result
        // No xCalls initiated from L2 to L1, so no need to prepopulate the L2 result inbox
        chainIds[0] = rollupId;
        results[0] = ""; // mintETH() return empty bytes
        resultHashes[0] = keccak256(""); // deposit() and mintETH() return empty bytes
        mainnet.fillResultsInbox(chainIds, resultHashes, results);

        // Deposit via mainnet shared bridge
        vm.prank(alice);
        mainnet.deposit{value: 1 ether}(rollupId, bob);

        // Reconstruct the outbound L1->L2 transaction
        // (Sequencer can use the CrossChainCall event data)
        ICrossChainCaller.CrossCall memory txn = ICrossChainCaller.CrossCall({
            to: mainnet.l2BridgeAddresses(rollupId),
            gasLimit: 21000 * 5,
            value: 1 ether,
            data: abi.encodeCall(IBridgeL2.mintETH, (bob))
        });

        // Execute the L2 privileged transaction handler
        // This will call the mintETH() function on the rollup
        vm.startPrank(address(rollup));
        rollup.xCallHandler(mainnetId, mainnet.l2BridgeAddresses(rollupId), nonce, txn);
        vm.stopPrank();

        // Verify balances are correct
        assertEq(alice.balance, 99 ether);
        assertEq(bob.balance, 1 ether);

        // Verify mailbox states
        ICrossChainCaller.MailboxCommitments memory mainnetMailboxCommitments = mainnet.readMailboxes(rollupId);
        ICrossChainCaller.MailboxCommitments memory rollupMailboxCommitments = rollup.readMailboxes(mainnetId);

        assertEq(
            mainnetMailboxCommitments.transactionsOutbox,
            rollupMailboxCommitments.transactionsInbox,
            "mainnet.transactionsOutbox != rollup.transactionsInbox"
        );
        assertEq(
            mainnetMailboxCommitments.transactionsInbox,
            rollupMailboxCommitments.transactionsOutbox,
            "mainnet.transactionsInbox != rollup.transactionsOutbox"
        );
        assertEq(
            mainnetMailboxCommitments.resultsInbox,
            rollupMailboxCommitments.resultsOutbox,
            "mainnet.resultsInbox != rollup.resultsOutbox"
        );
        assertEq(
            mainnetMailboxCommitments.resultsOutbox,
            rollupMailboxCommitments.resultsInbox,
            "mainnet.resultsOutbox != rollup.resultsInbox"
        );
    }

    function test_l2ToL1_withdrawal() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        uint256 nonce = 0;
        vm.deal(alice, 100 ether);
        uint256[] memory chainIds = new uint256[](1);
        bytes[] memory results = new bytes[](1);
        bytes32[] memory resultHashes = new bytes32[](1);

        // Prepopulate the L2 result inbox with withdraw() result
        // No xCalls initiated from L1 to L2, so no need to prepopulate the L1 result inbox
        chainIds[0] = mainnetId;
        results[0] = ""; // withdraw() return empty bytes
        resultHashes[0] = keccak256(""); // withdraw() return empty bytes
        rollup.fillResultsInbox(chainIds, resultHashes, results);

        // Pretend the rollup has 1 ETH locked already
        mainnet.editLockedEth(rollupId, 1 ether);
        vm.deal(address(mainnet), 1 ether);

        // Withdraw via rollup
        vm.prank(alice);
        rollup.withdraw{value: 1 ether}(mainnetId, bob);

        // Reconstruct the outbound L2->L1 transaction
        // (Sequencer can use the CrossChainCall event data)
        ICrossChainCaller.CrossCall memory txn = ICrossChainCaller.CrossCall({
            to: address(mainnet),
            gasLimit: 21000 * 5,
            value: 0,
            data: abi.encodeCall(ISharedBridge.handleWithdrawal, (rollupId, bob, 1 ether))
        });

        // Execute the L2 privileged transaction handler
        // This will call the handleWithdrawal() function on the mainnet
        vm.startPrank(sequencer);
        mainnet.xCallHandler(rollupId, address(rollup), nonce, txn);
        vm.stopPrank();

        // Verify balances are correct
        assertEq(alice.balance, 99 ether);
        assertEq(bob.balance, 1 ether);

        // Verify mailbox states
        ICrossChainCaller.MailboxCommitments memory mainnetMailboxCommitments = mainnet.readMailboxes(rollupId);
        ICrossChainCaller.MailboxCommitments memory rollupMailboxCommitments = rollup.readMailboxes(mainnetId);

        assertEq(
            mainnetMailboxCommitments.transactionsOutbox,
            rollupMailboxCommitments.transactionsInbox,
            "mainnet.transactionsOutbox != rollup.transactionsInbox"
        );
        assertEq(
            mainnetMailboxCommitments.transactionsInbox,
            rollupMailboxCommitments.transactionsOutbox,
            "mainnet.transactionsInbox != rollup.transactionsOutbox"
        );
        assertEq(
            mainnetMailboxCommitments.resultsInbox,
            rollupMailboxCommitments.resultsOutbox,
            "mainnet.resultsInbox != rollup.resultsOutbox"
        );
        assertEq(
            mainnetMailboxCommitments.resultsOutbox,
            rollupMailboxCommitments.resultsInbox,
            "mainnet.resultsOutbox != rollup.resultsInbox"
        );
    }
}
