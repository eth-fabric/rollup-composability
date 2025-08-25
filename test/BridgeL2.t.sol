// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IScopedCallable} from "../src/IScopedCallable.sol";
import {BridgeL2} from "../src/BridgeL2.sol";
import {IBridgeL2} from "../src/IBridgeL2.sol";
import {ISharedBridge} from "../src/ISharedBridge.sol";

contract MintETHTester is Test {
    BridgeL2 public rollup;
    uint256 public l1Id = 1;
    uint256 public rollupId = 2;
    address public sequencer = makeAddr("sequencer");
    address public l1Bridge = makeAddr("l1Bridge");

    function setUp() public {
        rollup = new BridgeL2(l1Bridge, rollupId, sequencer, makeAddr("owner"));

        vm.prank(sequencer);
        rollup.editSupportedChain(l1Id, true);

        // Give the rollup some ETH to mint
        vm.deal(address(rollup), 100 ether);
    }

    function test_mintETH() public {
        address from = makeAddr("alice");

        // Create a mintETH transaction for 1 ether
        IScopedCallable.ScopedRequest memory txn = IScopedCallable.ScopedRequest({
            to: address(rollup),
            gasLimit: 21000 * 5,
            value: 1 ether,
            data: abi.encodeCall(IBridgeL2.mintETH, (from))
        });

        // Execute mintETH privileged transaction
        // The sender address is the bridge itself
        vm.startPrank(address(rollup));
        rollup.handleScopedCall(l1Id, address(rollup), 0, txn);
        vm.stopPrank();

        // Verify mintETH worked
        assertEq(from.balance, 1 ether);

        // Verify mailbox states
        IScopedCallable.RollingHashes memory rollingHashes = rollup.getRollingHashes(l1Id);

        // Reconstruct the expected transaction hash
        bytes32 expectedHash = rollup.getTransactionHash(l1Id, rollupId, address(rollup), 0, txn);

        // Requests inbox should be populated with hash of the mintEth() tx
        assertEq(
            rollingHashes.requestsIn, keccak256(abi.encodePacked(bytes32(0), expectedHash)), "requestsIn incorrect"
        );

        // Responses outbox should be populated with hash of empty return value from the mintEth() call
        assertEq(
            rollingHashes.responsesOut, keccak256(abi.encodePacked(bytes32(0), keccak256(""))), "responsesOut incorrect"
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
        rollup = new BridgeL2(l1Bridge, rollupId, sequencer, makeAddr("owner"));

        vm.prank(sequencer);
        rollup.editSupportedChain(l1Id, true);
    }

    function test_withdrawal() public {
        address alice = makeAddr("alice");
        vm.deal(alice, 100 ether);

        // Call withdraw() on the rollup
        vm.prank(alice);
        rollup.withdraw{value: 1 ether}(l1Id, alice);

        // Verify withdrawal worked
        assertEq(alice.balance, 99 ether);

        // ---- Verify mailbox states ----
        IScopedCallable.RollingHashes memory rollingHashes = rollup.getRollingHashes(l1Id);

        // Reconstruct the expected outbound transaction from the withdraw() call
        IScopedCallable.ScopedRequest memory crossCall = IScopedCallable.ScopedRequest({
            to: rollup.l1Bridge(),
            gasLimit: 21000 * 5,
            value: 0,
            data: abi.encodeCall(ISharedBridge.handleWithdrawal, (rollupId, alice, 1 ether))
        });

        // Reconstruct the expected outbound transaction hash from the withdraw() call
        bytes32 expectedHash = rollup.getTransactionHash(
            rollupId, // src
            l1Id, // dst
            address(rollup), // xCall originates form rollup
            0,
            crossCall
        );

        // Verify transactionsOutbox correctly written
        assertEq(
            rollingHashes.requestsOut, keccak256(abi.encodePacked(bytes32(0), expectedHash)), "requestsOut incorrect"
        );
    }
}
