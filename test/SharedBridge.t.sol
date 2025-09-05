// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {SharedBridge} from "../src/SharedBridge.sol";
import {IScopedCallable} from "../src/IScopedCallable.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";

contract Foo {
    function bar() public payable returns (uint256) {
        return 42;
    }
}

contract CrossChainCallTester is Test {
    SharedBridge public sendingBridge;
    SharedBridge public receivingBridge;
    Foo public foo;
    bytes public sendingBridgeAddress;
    bytes public receivingBridgeAddress;
    address owner = makeAddr("owner");
    address gateway = makeAddr("gateway");

    function setUp() public {
        address[] memory gateways = new address[](1);
        gateways[0] = gateway;
        bytes4[] memory attributes = new bytes4[](1);
        attributes[0] = 0x00000000;

        foo = new Foo();
        sendingBridge = new SharedBridge(owner, gateways, attributes);
        receivingBridge = new SharedBridge(owner, gateways, attributes);

        // For local testing, we use the same chainid for both
        sendingBridgeAddress = InteroperableAddress.formatEvmV1(block.chainid, address(sendingBridge));
        receivingBridgeAddress = InteroperableAddress.formatEvmV1(block.chainid, address(receivingBridge));

        // Register the remote bridges
        vm.prank(owner);
        sendingBridge.registerRemoteBridge(receivingBridgeAddress);
        vm.prank(owner);
        receivingBridge.registerRemoteBridge(sendingBridgeAddress);

        // Set up some initial balance for the bridges
        vm.deal(address(sendingBridge), 10000 ether);
        vm.deal(address(receivingBridge), 10000 ether);
    }

    function test_sendAndReceiveMessage() public {
        address alice = makeAddr("alice");
        uint256 value = 100 ether;
        vm.deal(alice, value);

        // Alice as an interoperable address
        bytes memory sender = InteroperableAddress.formatEvmV1(block.chainid, alice);

        // Foo as an interoperable address
        bytes memory recipient = InteroperableAddress.formatEvmV1(block.chainid, address(foo));

        // Nonce at start of test
        uint256 nonce = 0;

        // Request to call foo.bar() on chainB
        bytes memory data = abi.encodeWithSelector(Foo.bar.selector);

        // Figure out what the requestHash will be
        bytes memory wrappedPayload = abi.encode(++nonce, sender, recipient, value, data);
        bytes32 requestHash = keccak256(wrappedPayload);
        bytes32 sendId = sendingBridge._calcStorageKey(receivingBridgeAddress, requestHash);

        // Assume sequencer has simulated ahead of time to determine the response
        bytes[] memory bridges = new bytes[](1);
        bytes32[] memory requestHashes = new bytes32[](1);
        bytes[] memory simulatedResponses = new bytes[](1);
        bridges[0] = receivingBridgeAddress;
        requestHashes[0] = requestHash;
        simulatedResponses[0] = abi.encode(foo.bar()); // The "simulated" response

        // Pre-populate sendingBridge's inbox with simulated responses
        sendingBridge.fillResponsesIn(bridges, requestHashes, simulatedResponses);

        // Call the executeMessage handler on receivingBridge (would be called in their rollup execution environment)
        vm.prank(gateway); // must be called by the whitelisted gateway
        receivingBridge.receiveMessage(sendId, sender, wrappedPayload);

        // Call the sendMessage on sendingBridge
        bytes[] memory attributes = new bytes[](1);
        vm.prank(alice); // must be called by the sender
        bytes32 gotSendId = sendingBridge.sendMessage{value: value}(recipient, data, attributes);

        // Read the response from the inbox
        bytes memory response = sendingBridge.readResponsesInboxValue(gotSendId);

        // Check the response value returned correctly
        assertEq(response, simulatedResponses[0], "response should be equal to expected response");

        // Check the response value written correctly and hashed correctly
        assertEq(
            sendingBridge.readRollingHash(receivingBridgeAddress, IScopedCallable.RollingHashType.RESPONSES_IN),
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
            sendingBridge.readRollingHash(receivingBridgeAddress, IScopedCallable.RollingHashType.REQUESTS_OUT),
            receivingBridge.readRollingHash(sendingBridgeAddress, IScopedCallable.RollingHashType.REQUESTS_IN),
            "sendingBridge's requestsOutbox should be equal to receivingBridge's requestsInbox"
        );

        // ChainA received responses from ChainB in order
        assertEq(
            sendingBridge.readRollingHash(receivingBridgeAddress, IScopedCallable.RollingHashType.RESPONSES_OUT),
            receivingBridge.readRollingHash(sendingBridgeAddress, IScopedCallable.RollingHashType.RESPONSES_IN),
            "sendingBridge's responsesOutbox should be equal to receivingBridge's responsesInbox"
        );

        // ChainB received responses from ChainA in order
        assertEq(
            sendingBridge.readRollingHash(receivingBridgeAddress, IScopedCallable.RollingHashType.RESPONSES_IN),
            receivingBridge.readRollingHash(sendingBridgeAddress, IScopedCallable.RollingHashType.RESPONSES_OUT),
            "sendingBridge's responsesInbox should be equal to receivingBridge's responsesOutbox"
        );

        // ChainA handled receiveMessage requests from ChainB in order
        assertEq(
            sendingBridge.readRollingHash(receivingBridgeAddress, IScopedCallable.RollingHashType.REQUESTS_IN),
            receivingBridge.readRollingHash(sendingBridgeAddress, IScopedCallable.RollingHashType.REQUESTS_OUT),
            "sendingBridge's requestsInbox should be equal to receivingBridge's requestsOutbox"
        );

        // Check alice's balance decreased
        assertEq(alice.balance, 0);
        assertEq(address(foo).balance, value);
    }
}
