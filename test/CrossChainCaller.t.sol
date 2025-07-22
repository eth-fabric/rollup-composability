// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {CrossChainCaller} from "../src/CrossChainCaller.sol";
import {ICrossChainCaller} from "../src/ICrossChainCaller.sol";

contract Foo {
    function bar() public pure returns (uint256) {
        return 42;
    }
}

contract CrossChainCallerTester is Test {
    CrossChainCaller public chainA;
    CrossChainCaller public chainB;
    Foo public foo;
    uint256 public chainAId = 1;
    uint256 public chainBId = 2;

    function setUp() public {
        chainA = new CrossChainCaller(chainAId);
        chainB = new CrossChainCaller(chainBId);
        foo = new Foo();
    }

    function test_xCall() public {
        address from = makeAddr("alice");
        uint256 nonce = chainA.globalXCallNonce();

        ICrossChainCaller.CrossCall memory txn = ICrossChainCaller.CrossCall({
            to: address(foo),
            value: 0,
            gasLimit: 1000000,
            data: abi.encodeWithSelector(Foo.bar.selector)
        });

        bytes32 txHash = chainA.getTransactionHash(chainAId, chainBId, from, nonce, txn);

        // Assume sequencer has simulated ahead of time
        uint256[] memory chainIds = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        bytes[] memory results = new bytes[](1);
        chainIds[0] = chainBId;
        txHashes[0] = txHash;
        results[0] = abi.encode(foo.bar());

        // Pre-populate chainA's inbox with results
        chainA.fillResultsInbox(chainIds, txHashes, results);

        // Call the xCallHandler on chainB (would be called in their rollup execution environment)
        chainB.xCallHandler(chainAId, from, nonce, txn);

        // Call the xCall on chainA
        bytes memory result = chainA.xCall(chainBId, from, txn);

        // Check the result value returned correctly
        assertEq(result, abi.encode(foo.bar()));

        // Check the result value written correctly and hashed correctly
        assertEq(
            chainA.resultsInbox(chainBId),
            keccak256(
                abi.encodePacked(
                    bytes32(0), // rolling hash is building on empty bytes32
                    keccak256(chainA.resultsInboxValues(chainBId, txHash))
                )
            )
        );

        // MAILBOX EQUIVALENCE CHECKS

        // ChainB executed xCall transactions from ChainA in order
        assertEq(chainA.transactionOutbox(chainBId), chainB.transactionInbox(chainAId));

        // ChainA received results from ChainB in order
        assertEq(chainA.resultsInbox(chainBId), chainB.resultsOutbox(chainAId));

        // ChainB received results from ChainA in order
        assertEq(chainA.resultsOutbox(chainBId), chainB.resultsInbox(chainAId));

        // ChainA executed xCall transactions from ChainB in order
        assertEq(chainA.transactionInbox(chainBId), chainB.transactionOutbox(chainAId));
    }
}
