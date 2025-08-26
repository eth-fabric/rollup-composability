// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import {Test, console} from "forge-std/Test.sol";
// import {IScopedCallable} from "../src/IScopedCallable.sol";
// import {SharedBridge} from "../src/SharedBridge.sol";
// import {ISharedBridge} from "../src/ISharedBridge.sol";
// import {IBridgeL2} from "../src/IBridgeL2.sol";

// contract DepositTester is Test {
//     SharedBridge public chainA;
//     uint256 public chainAId = 1;
//     uint256 public chainBId = 2;
//     address public sequencer = makeAddr("sequencer");

//     function setUp() public {
//         chainA = new SharedBridge(sequencer, chainAId);

//         vm.prank(sequencer);
//         chainA.editSupportedChain(chainBId, true);

//         vm.prank(sequencer);
//         chainA.setL2BridgeAddress(chainBId, makeAddr("chainB"));
//     }

//     function test_deposit() public {
//         address from = makeAddr("alice");
//         vm.deal(from, 100 ether);

//         // Verify reverts on unsupported chain
//         vm.prank(from);
//         vm.expectRevert(abi.encodeWithSelector(IScopedCallable.UnsupportedChain.selector));
//         chainA.deposit{value: 1 ether}(chainAId, from);

//         // Verify deposit on supported chain
//         vm.prank(from);
//         chainA.deposit{value: 1 ether}(chainBId, from);

//         // Reconstruct the expected transaction hash
//         bytes32 expectedHash = chainA.getTransactionHash(
//             chainAId,
//             chainBId,
//             chainA.l2BridgeAddresses(chainBId),
//             0,
//             IScopedCallable.ScopedRequest({
//                 to: chainA.l2BridgeAddresses(chainBId),
//                 value: 1 ether,
//                 gasLimit: 21000 * 5,
//                 data: abi.encodeCall(IBridgeL2.mintETH, (from))
//             })
//         );
//         // Verify mailbox states
//         IScopedCallable.RollingHashes memory rollingHashes = chainA.getRollingHashes(chainBId);

//         // Verify transactionsOutbox correctly written
//         assertEq(
//             rollingHashes.requestsOut, keccak256(abi.encodePacked(bytes32(0), expectedHash)), "requestsOut incorrect"
//         );
//     }
// }

// contract WithdrawalTester is Test {
//     SharedBridge public chainA;
//     uint256 public chainAId = 1;
//     uint256 public chainBId = 2;
//     address public sequencer = makeAddr("sequencer");

//     function setUp() public {
//         chainA = new SharedBridge(sequencer, chainAId);

//         vm.prank(sequencer);
//         chainA.editSupportedChain(chainBId, true);

//         vm.prank(sequencer);
//         chainA.setL2BridgeAddress(chainBId, makeAddr("chainB"));
//     }

//     function test_withdrawal() public {
//         address from = makeAddr("alice");
//         vm.deal(from, 100 ether);

//         // Deposit 1 ether to SharedBridge
//         vm.prank(from);
//         chainA.deposit{value: 1 ether}(chainBId, from);

//         // Verify deposit worked
//         assertEq(from.balance, 99 ether);
//         assertEq(address(chainA).balance, 1 ether);

//         // Create a withdrawal transaction for 1 ether
//         IScopedCallable.ScopedRequest memory txn = IScopedCallable.ScopedRequest({
//             to: address(chainA),
//             gasLimit: 21000 * 5,
//             value: 0,
//             data: abi.encodeCall(ISharedBridge.handleWithdrawal, (chainBId, from, 1 ether))
//         });

//         // Execute withdrawal transaction
//         vm.startPrank(sequencer);
//         chainA.handleScopedCall(chainBId, chainA.l2BridgeAddresses(chainBId), 0, txn);
//         vm.stopPrank();

//         // Verify withdrawal worked
//         assertEq(from.balance, 100 ether);
//         assertEq(address(chainA).balance, 0 ether);

//         // ---- Verify mailbox states ----
//         IScopedCallable.RollingHashes memory rollingHashes = chainA.getRollingHashes(chainBId);

//         // Verify transactionsOutbox correctly written from the deposit() call
//         bytes32 expectedHash = chainA.getTransactionHash(
//             chainAId,
//             chainBId,
//             chainA.l2BridgeAddresses(chainBId),
//             0,
//             IScopedCallable.ScopedRequest({
//                 to: chainA.l2BridgeAddresses(chainBId),
//                 value: 1 ether,
//                 gasLimit: 21000 * 5,
//                 data: abi.encodeCall(IBridgeL2.mintETH, (from))
//             })
//         );
//         assertEq(
//             rollingHashes.requestsOut, keccak256(abi.encodePacked(bytes32(0), expectedHash)), "requestsOut incorrect"
//         );

//         // Reconstruct the expected inbound transaction hash from the handleWithdrawal() call
//         expectedHash = chainA.getTransactionHash(chainBId, chainAId, chainA.l2BridgeAddresses(chainBId), 0, txn);

//         // Verify requestsInbox correctly written
//         assertEq(
//             rollingHashes.requestsIn, keccak256(abi.encodePacked(bytes32(0), expectedHash)), "requestsIn incorrect"
//         );

//         // Results outbox should be populated with hash of empty return value from the handleWithdrawal() call
//         assertEq(
//             rollingHashes.responsesOut, keccak256(abi.encodePacked(bytes32(0), keccak256(""))), "responsesOut incorrect"
//         );
//     }
// }
