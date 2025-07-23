// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {CrossChainCaller} from "../src/CrossChainCaller.sol";
import {ICrossChainCaller} from "../src/ICrossChainCaller.sol";
import {SharedBridge} from "../src/SharedBridge.sol";
import {ISharedBridge} from "../src/ISharedBridge.sol";
import {IBridgeL2} from "../src/IBridgeL2.sol";

contract DepositTester is Test {
    SharedBridge public chainA;
    uint256 public chainAId = 1;
    uint256 public chainBId = 2;
    address public onChainProposer = makeAddr("onChainProposer");

    function setUp() public {
        chainA = new SharedBridge(onChainProposer, chainAId);

        vm.prank(onChainProposer);
        chainA.editSupportedChain(chainBId, true);
    }

    function test_deposit() public {
        address from = makeAddr("alice");
        vm.deal(from, 100 ether);

        // Verify reverts on unsupported chain
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(ISharedBridge.UnsupportedChain.selector));
        chainA.deposit{value: 1 ether}(chainAId, from);

        // Verify deposit on supported chain
        vm.prank(from);
        chainA.deposit{value: 1 ether}(chainBId, from);

        // Reconstruct the expected transaction hash
        bytes32 expectedHash = chainA.getTransactionHash(
            chainAId,
            chainBId,
            from,
            0,
            ICrossChainCaller.CrossCall({
                to: chainA.L2_BRIDGE_ADDRESS(),
                value: 1 ether,
                gasLimit: 21000 * 5,
                data: abi.encodeCall(IBridgeL2.mintETH, (from))
            })
        );

        // Verify transactionsOutbox correctly written
        assertEq(
            chainA.readRollingHash(chainBId, ICrossChainCaller.MailboxType.TRANSACTIONS_OUTBOX),
            keccak256(abi.encodePacked(bytes32(0), expectedHash)),
            "transactionOutbox incorrect"
        );
    }
}
