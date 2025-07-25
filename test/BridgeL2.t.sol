// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {BridgeL2} from "../src/BridgeL2.sol";
import {ICrossChainCaller} from "../src/ICrossChainCaller.sol";
import {IBridgeL2} from "../src/IBridgeL2.sol";
import {ISharedBridge} from "../src/ISharedBridge.sol";

contract MintETHTester is Test {
    BridgeL2 public rollup;
    uint256 public l1Id = 1;
    uint256 public rollupId = 2;
    address public sequencer = makeAddr("sequencer");
    address public l1Bridge = makeAddr("l1Bridge");

    function setUp() public {
        rollup = new BridgeL2(l1Bridge, rollupId, sequencer);

        vm.prank(sequencer);
        rollup.editSupportedChain(l1Id, true);

        // Give the rollup some ETH to mint
        vm.deal(address(rollup), 100 ether);
    }

    function test_mintETH() public {
        address from = makeAddr("alice");

        // Create a mintETH transaction for 1 ether
        ICrossChainCaller.CrossCall memory txn = ICrossChainCaller.CrossCall({
            to: address(rollup),
            gasLimit: 21000 * 5,
            value: 1 ether,
            data: abi.encodeCall(IBridgeL2.mintETH, (from))
        });

        // Execute mintETH privileged transaction
        // The sender address is the bridge itself
        vm.startPrank(address(rollup));
        rollup.xCallHandler(l1Id, address(rollup), 0, txn);
        vm.stopPrank();

        // Verify mintETH worked
        assertEq(from.balance, 1 ether);

        // Verify mailbox states
        ICrossChainCaller.MailboxCommitments memory mailboxCommitments = rollup.readMailboxes(l1Id);

        // Reconstruct the expected transaction hash
        bytes32 expectedHash = rollup.getTransactionHash(l1Id, rollupId, address(rollup), 0, txn);

        // Transactions inbox should be populated with hash of the mintEth() tx
        assertEq(
            mailboxCommitments.transactionsInbox,
            keccak256(abi.encodePacked(bytes32(0), expectedHash)),
            "transactionsInbox incorrect"
        );

        // Results outbox should be populated with hash of empty return value from the mintEth() call
        assertEq(
            mailboxCommitments.resultsOutbox,
            keccak256(abi.encodePacked(bytes32(0), keccak256(""))),
            "resultsOutbox incorrect"
        );
    }
}

contract WithdrawalTester is Test {
    BridgeL2 public rollup;
    uint256 public l1Id = 1;
    uint256 public rollupId = 2;
    address public sequencer = makeAddr("sequencer");
    address public l1Bridge = makeAddr("l1Bridge");

    function setUp() public {
        rollup = new BridgeL2(l1Bridge, rollupId, sequencer);

        vm.prank(sequencer);
        rollup.editSupportedChain(l1Id, true);
    }

    function test_withdrawal() public {
        address from = makeAddr("alice");
        vm.deal(from, 100 ether);

        // Call withdraw() on the rollup
        vm.prank(from);
        rollup.withdraw{value: 1 ether}(l1Id, from);

        // Verify withdrawal worked
        assertEq(from.balance, 99 ether);

        // ---- Verify mailbox states ----
        ICrossChainCaller.MailboxCommitments memory mailboxCommitments = rollup.readMailboxes(l1Id);

        // Reconstruct the expected outbound transaction from the withdraw() call
        ICrossChainCaller.CrossCall memory crossCall = ICrossChainCaller.CrossCall({
            to: rollup.L1_BRIDGE(),
            gasLimit: 21000 * 5,
            value: 0,
            data: abi.encodeCall(ISharedBridge.handleWithdrawal, (rollupId, from, 1 ether))
        });

        // Reconstruct the expected outbound transaction hash from the withdraw() call
        bytes32 expectedHash = rollup.getTransactionHash(
            rollupId, // src
            l1Id, // dst
            from, // from
            0,
            crossCall
        );

        // Verify transactionsOutbox correctly written
        assertEq(
            mailboxCommitments.transactionsOutbox,
            keccak256(abi.encodePacked(bytes32(0), expectedHash)),
            "transactionOutbox incorrect"
        );
    }
}
