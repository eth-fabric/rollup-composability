// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ICrossChainCaller} from "../src/ICrossChainCaller.sol";
import {SharedBridge} from "../src/SharedBridge.sol";
import {ISharedBridge} from "../src/ISharedBridge.sol";
import {IBridgeL2} from "../src/IBridgeL2.sol";

contract DepositTester is Test {
    SharedBridge public chainA;
    uint256 public chainAId = 1;
    uint256 public chainBId = 2;
    address public sequencer = makeAddr("sequencer");

    function setUp() public {
        chainA = new SharedBridge(sequencer, chainAId);

        vm.prank(sequencer);
        chainA.editSupportedChain(chainBId, true);
    }

    function test_deposit() public {
        address from = makeAddr("alice");
        vm.deal(from, 100 ether);

        // Verify reverts on unsupported chain
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(ICrossChainCaller.UnsupportedChain.selector));
        chainA.deposit{value: 1 ether}(chainAId, from);

        // Verify deposit on supported chain
        vm.prank(from);
        chainA.deposit{value: 1 ether}(chainBId, from);

        // Reconstruct the expected transaction hash
        bytes32 expectedHash = chainA.getTransactionHash(
            chainAId,
            chainBId,
            chainA.L2_BRIDGE_ADDRESS(),
            0,
            ICrossChainCaller.CrossCall({
                to: chainA.L2_BRIDGE_ADDRESS(),
                value: 1 ether,
                gasLimit: 21000 * 5,
                data: abi.encodeCall(IBridgeL2.mintETH, (from))
            })
        );
        // Verify mailbox states
        ICrossChainCaller.MailboxCommitments memory mailboxCommitments = chainA.readMailboxes(chainBId);

        // Verify transactionsOutbox correctly written
        assertEq(
            mailboxCommitments.transactionsOutbox,
            keccak256(abi.encodePacked(bytes32(0), expectedHash)),
            "transactionOutbox incorrect"
        );
    }
}

contract WithdrawalTester is Test {
    SharedBridge public chainA;
    uint256 public chainAId = 1;
    uint256 public chainBId = 2;
    address public sequencer = makeAddr("sequencer");

    function setUp() public {
        chainA = new SharedBridge(sequencer, chainAId);

        vm.prank(sequencer);
        chainA.editSupportedChain(chainBId, true);
    }

    function test_withdrawal() public {
        address from = makeAddr("alice");
        vm.deal(from, 100 ether);

        // Deposit 1 ether to SharedBridge
        vm.prank(from);
        chainA.deposit{value: 1 ether}(chainBId, from);

        // Verify deposit worked
        assertEq(from.balance, 99 ether);
        assertEq(address(chainA).balance, 1 ether);

        // Create a withdrawal transaction for 1 ether
        ICrossChainCaller.CrossCall memory txn = ICrossChainCaller.CrossCall({
            to: address(chainA),
            gasLimit: 21000 * 5,
            value: 0,
            data: abi.encodeCall(ISharedBridge.handleWithdrawal, (chainBId, from, 1 ether))
        });

        // Execute withdrawal transaction
        vm.startPrank(sequencer);
        chainA.xCallHandler(chainBId, chainA.L2_BRIDGE_ADDRESS(), 0, txn);
        vm.stopPrank();

        // Verify withdrawal worked
        assertEq(from.balance, 100 ether);
        assertEq(address(chainA).balance, 0 ether);

        // ---- Verify mailbox states ----
        ICrossChainCaller.MailboxCommitments memory mailboxCommitments = chainA.readMailboxes(chainBId);

        // Verify transactionsOutbox correctly written from the deposit() call
        bytes32 expectedHash = chainA.getTransactionHash(
            chainAId,
            chainBId,
            chainA.L2_BRIDGE_ADDRESS(),
            0,
            ICrossChainCaller.CrossCall({
                to: chainA.L2_BRIDGE_ADDRESS(),
                value: 1 ether,
                gasLimit: 21000 * 5,
                data: abi.encodeCall(IBridgeL2.mintETH, (from))
            })
        );
        assertEq(
            mailboxCommitments.transactionsOutbox,
            keccak256(abi.encodePacked(bytes32(0), expectedHash)),
            "transactionOutbox incorrect"
        );

        // Reconstruct the expected inbound transaction hash from the handleWithdrawal() call
        expectedHash = chainA.getTransactionHash(chainBId, chainAId, chainA.L2_BRIDGE_ADDRESS(), 0, txn);

        // Verify transactionsInbox correctly written
        assertEq(
            mailboxCommitments.transactionsInbox,
            keccak256(abi.encodePacked(bytes32(0), expectedHash)),
            "transactionInbox incorrect"
        );

        // Results outbox should be populated with hash of empty return value from the handleWithdrawal() call
        assertEq(
            mailboxCommitments.resultsOutbox,
            keccak256(abi.encodePacked(bytes32(0), keccak256(""))),
            "resultsOutbox incorrect"
        );
    }
}
