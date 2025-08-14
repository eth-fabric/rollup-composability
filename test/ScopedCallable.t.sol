// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ScopedCallable} from "../src/ScopedCallable.sol";
import {IScopedCallable} from "../src/IScopedCallable.sol";
import {IBridgeL2} from "../src/IBridgeL2.sol";
import {ISharedBridge} from "../src/ISharedBridge.sol";

contract Foo {
    function bar() public pure returns (uint256) {
        return 42;
    }
}

contract ScopedCallableImpl is ScopedCallable {
    constructor(uint256 chainId) ScopedCallable(chainId) {}

    function scopedCall(uint256 targetChainId, address from, IScopedCallable.ScopedRequest calldata txn)
        external
        returns (bytes memory)
    {
        return _scopedCall(targetChainId, from, txn);
    }

    function handleScopedCall(
        uint256 sourceChainId,
        address from,
        uint256 nonce,
        IScopedCallable.ScopedRequest calldata txn
    ) external {
        _handleScopedCall(sourceChainId, from, nonce, txn);
    }
}

contract CrossChainCallerTester is Test {
    ScopedCallableImpl public chainA;
    ScopedCallableImpl public chainB;
    Foo public foo;
    uint256 public chainAId = 1;
    uint256 public chainBId = 2;

    function setUp() public {
        chainA = new ScopedCallableImpl(chainAId);
        chainB = new ScopedCallableImpl(chainBId);
        foo = new Foo();
    }

    function test_scopedCall() public {
        address from = makeAddr("alice");
        uint256 nonce = chainA.globalScopedCallNonce();

        IScopedCallable.ScopedRequest memory txn = IScopedCallable.ScopedRequest({
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
        chainA.fillResponsesIn(chainIds, txHashes, results);

        // Call the xCallHandler on chainB (would be called in their rollup execution environment)
        chainB.handleScopedCall(chainAId, from, nonce, txn);

        // Call the xCall on chainA
        bytes memory response = chainA.scopedCall(chainBId, from, txn);

        // Check the result value returned correctly
        assertEq(response, abi.encode(foo.bar()));

        // Check the result value written correctly and hashed correctly
        assertEq(
            chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.RESPONSES_IN),
            keccak256(
                abi.encodePacked(
                    bytes32(0), // rolling hash is building on empty bytes32
                    keccak256(chainA.readResponsesInboxValue(chainBId, txHash))
                )
            )
        );

        // MAILBOX EQUIVALENCE CHECKS

        // ChainB handled scopedCall requests from ChainA in order
        assertEq(
            chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.REQUESTS_OUT),
            chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.REQUESTS_IN),
            "A's requestsOutbox should be equal to B's requestsInbox"
        );

        // ChainA received responses from ChainB in order
        assertEq(
            chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.RESPONSES_OUT),
            chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.RESPONSES_IN),
            "A's responsesOutbox should be equal to B's responsesInbox"
        );

        // ChainB received responses from ChainA in order
        assertEq(
            chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.RESPONSES_IN),
            chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.RESPONSES_OUT),
            "A's responsesInbox should be equal to B's responsesOutbox"
        );

        // ChainA handled scopedCall requests from ChainB in order
        assertEq(
            chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.REQUESTS_IN),
            chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.REQUESTS_OUT),
            "A's requestsInbox should be equal to B's requestsOutbox"
        );
    }
}
