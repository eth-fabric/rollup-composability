// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {SharedBridge} from "../src/SharedBridge.sol";
import {IScopedCallable} from "../src/IScopedCallable.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";

contract Foo {
    function bar() public pure returns (uint256) {
        return 42;
    }
}

contract CrossChainCallTester is Test {
    SharedBridge public bridgeA;
    SharedBridge public bridgeB;
    Foo public foo;
    bytes public bridgeAId;
    bytes public bridgeBId;
    address owner = makeAddr("owner");
    address gateway = makeAddr("gateway");

    function setUp() public {
        address[] memory gateways = new address[](1);
        gateways[0] = gateway;
        bytes4[] memory attributes = new bytes4[](1);
        attributes[0] = 0x00000000;

        foo = new Foo();
        bridgeA = new SharedBridge(owner, gateways, attributes);
        bridgeB = new SharedBridge(owner, gateways, attributes);

        // For local testing, we use the same chainid for both
        bridgeAId = InteroperableAddress.formatEvmV1(block.chainid, address(bridgeA));
        bridgeBId = InteroperableAddress.formatEvmV1(block.chainid, address(bridgeB));

        // Register the remote bridges
        vm.prank(owner);
        bridgeA.registerRemoteBridge(bridgeBId);
        vm.prank(owner);
        bridgeB.registerRemoteBridge(bridgeAId);
    }

    function test_sendAndReceiveMessage() public {
        uint256 nonce = 0;

        // Request to call foo.bar() on chainB
        SharedBridge.Request memory request =
            SharedBridge.Request({to: address(foo), gasLimit: 1000000, data: abi.encodeWithSelector(Foo.bar.selector)});

        // Figure out the requestHash
        bytes memory unwrappedPayload = abi.encode(request);
        bytes memory wrappedPayload = abi.encode(++nonce, bridgeAId, bridgeBId, 0, unwrappedPayload);
        bytes32 requestHash = keccak256(wrappedPayload);
        bytes32 sendId = bridgeA._calcStorageKey(bridgeBId, requestHash);

        // Assume sequencer has simulated ahead of time to determine the response
        bytes[] memory bridges = new bytes[](1);
        bytes32[] memory requestHashes = new bytes32[](1);
        bytes[] memory simulatedResponses = new bytes[](1);
        bridges[0] = bridgeBId;
        requestHashes[0] = requestHash;
        simulatedResponses[0] = abi.encode(foo.bar()); // The "simulated" response

        // Pre-populate chainA's inbox with simulated responses
        bridgeA.fillResponsesIn(bridges, requestHashes, simulatedResponses);

        // Call the executeMessage handler on chainB (would be called in their rollup execution environment)
        vm.prank(gateway);
        bridgeB.receiveMessage(sendId, bridgeAId, wrappedPayload);

        // Call the sendMessage on chainA
        bytes[] memory attributes = new bytes[](1);
        vm.prank(gateway);
        bytes32 requestLocation = bridgeA.sendMessage(bridgeBId, unwrappedPayload, attributes);

        // Read the response from the inbox
        bytes memory response = bridgeA.readResponsesInboxValue(requestLocation);

        // Check the response value returned correctly
        assertEq(response, simulatedResponses[0], "response should be equal to expected response");

        // Check the response value written correctly and hashed correctly
        assertEq(
            bridgeA.readRollingHash(bridgeBId, IScopedCallable.RollingHashType.RESPONSES_IN),
            keccak256(
                abi.encodePacked(
                    bytes32(0), // rolling hash is building on empty bytes32
                    keccak256(response)
                )
            )
        );

        // MAILBOX EQUIVALENCE CHECKS

        // ChainB handled sendMessage requests from ChainA in order
        assertEq(
            bridgeA.readRollingHash(bridgeBId, IScopedCallable.RollingHashType.REQUESTS_OUT),
            bridgeB.readRollingHash(bridgeAId, IScopedCallable.RollingHashType.REQUESTS_IN),
            "A's requestsOutbox should be equal to B's requestsInbox"
        );

        // ChainA received responses from ChainB in order
        assertEq(
            bridgeA.readRollingHash(bridgeBId, IScopedCallable.RollingHashType.RESPONSES_OUT),
            bridgeB.readRollingHash(bridgeAId, IScopedCallable.RollingHashType.RESPONSES_IN),
            "A's responsesOutbox should be equal to B's responsesInbox"
        );

        // ChainB received responses from ChainA in order
        assertEq(
            bridgeA.readRollingHash(bridgeBId, IScopedCallable.RollingHashType.RESPONSES_IN),
            bridgeB.readRollingHash(bridgeAId, IScopedCallable.RollingHashType.RESPONSES_OUT),
            "A's responsesInbox should be equal to B's responsesOutbox"
        );

        // ChainA handled receiveMessage requests from ChainB in order
        assertEq(
            bridgeA.readRollingHash(bridgeBId, IScopedCallable.RollingHashType.REQUESTS_IN),
            bridgeB.readRollingHash(bridgeAId, IScopedCallable.RollingHashType.REQUESTS_OUT),
            "A's requestsInbox should be equal to B's requestsOutbox"
        );
    }
}
