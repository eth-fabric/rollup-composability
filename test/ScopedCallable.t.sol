// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ScopedCallable} from "../src/ScopedCallable.sol";
import {IScopedCallable} from "../src/IScopedCallable.sol";

contract ScopedCallableTest is Test {
    ScopedCallable public scopedCallable;

    // Test data
    bytes public bridge1 = "bridge1";
    bytes public bridge2 = "bridge2";
    bytes32 public requestHash1 = keccak256("request1");
    bytes32 public requestHash2 = keccak256("request2");
    bytes public response1 = "response1";
    bytes public response2 = "response2";

    function setUp() public {
        scopedCallable = new ScopedCallable();
    }

    // ===================================================
    // fillResponsesIn Tests
    // ===================================================

    function test_fillResponsesIn_SingleResponse() public {
        bytes[] memory bridges = new bytes[](1);
        bytes32[] memory requestHashes = new bytes32[](1);
        bytes[] memory responses = new bytes[](1);

        bridges[0] = bridge1;
        requestHashes[0] = requestHash1;
        responses[0] = response1;

        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);

        // Verify response was stored correctly
        bytes32 responseLocation =
            keccak256(abi.encode(IScopedCallable.RollingHashType.RESPONSES_IN_VALUES, bridge1, requestHash1));
        bytes memory storedResponse = scopedCallable.readResponsesInboxValue(responseLocation);
        assertEq(storedResponse, response1, "Response should be stored correctly");

        // Verify rolling hash was updated
        bytes32 expectedRollingHash = keccak256(abi.encodePacked(bytes32(0), keccak256(response1)));
        bytes32 actualRollingHash =
            scopedCallable.readRollingHash(bridge1, IScopedCallable.RollingHashType.RESPONSES_IN);
        assertEq(actualRollingHash, expectedRollingHash, "Rolling hash should be updated correctly");
    }

    function test_fillResponsesIn_MultipleResponses() public {
        bytes[] memory bridges = new bytes[](2);
        bytes32[] memory requestHashes = new bytes32[](2);
        bytes[] memory responses = new bytes[](2);

        bridges[0] = bridge1;
        bridges[1] = bridge2;
        requestHashes[0] = requestHash1;
        requestHashes[1] = requestHash2;
        responses[0] = response1;
        responses[1] = response2;

        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);

        // Verify first response
        bytes32 responseLocation1 =
            keccak256(abi.encode(IScopedCallable.RollingHashType.RESPONSES_IN_VALUES, bridge1, requestHash1));
        bytes memory storedResponse1 = scopedCallable.readResponsesInboxValue(responseLocation1);
        assertEq(storedResponse1, response1, "First response should be stored correctly");

        // Verify second response
        bytes32 responseLocation2 =
            keccak256(abi.encode(IScopedCallable.RollingHashType.RESPONSES_IN_VALUES, bridge2, requestHash2));
        bytes memory storedResponse2 = scopedCallable.readResponsesInboxValue(responseLocation2);
        assertEq(storedResponse2, response2, "Second response should be stored correctly");

        // Verify rolling hashes were updated
        bytes32 expectedRollingHash1 = keccak256(abi.encodePacked(bytes32(0), keccak256(response1)));
        bytes32 actualRollingHash1 =
            scopedCallable.readRollingHash(bridge1, IScopedCallable.RollingHashType.RESPONSES_IN);
        assertEq(actualRollingHash1, expectedRollingHash1, "First rolling hash should be updated correctly");

        bytes32 expectedRollingHash2 = keccak256(abi.encodePacked(bytes32(0), keccak256(response2)));
        bytes32 actualRollingHash2 =
            scopedCallable.readRollingHash(bridge2, IScopedCallable.RollingHashType.RESPONSES_IN);
        assertEq(actualRollingHash2, expectedRollingHash2, "Second rolling hash should be updated correctly");
    }

    function test_fillResponsesIn_SequentialUpdates() public {
        // First update
        bytes[] memory bridges1 = new bytes[](1);
        bytes32[] memory requestHashes1 = new bytes32[](1);
        bytes[] memory responses1 = new bytes[](1);

        bridges1[0] = bridge1;
        requestHashes1[0] = requestHash1;
        responses1[0] = response1;

        scopedCallable.fillResponsesIn(bridges1, requestHashes1, responses1);

        // Second update to same bridge
        bytes[] memory bridges2 = new bytes[](1);
        bytes32[] memory requestHashes2 = new bytes32[](1);
        bytes[] memory responses2 = new bytes[](1);

        bridges2[0] = bridge1;
        requestHashes2[0] = requestHash2;
        responses2[0] = response2;

        scopedCallable.fillResponsesIn(bridges2, requestHashes2, responses2);

        // Verify both responses are stored
        bytes32 responseLocation1 =
            keccak256(abi.encode(IScopedCallable.RollingHashType.RESPONSES_IN_VALUES, bridge1, requestHash1));
        bytes memory storedResponse1 = scopedCallable.readResponsesInboxValue(responseLocation1);
        assertEq(storedResponse1, response1, "First response should still be stored");

        bytes32 responseLocation2 =
            keccak256(abi.encode(IScopedCallable.RollingHashType.RESPONSES_IN_VALUES, bridge1, requestHash2));
        bytes memory storedResponse2 = scopedCallable.readResponsesInboxValue(responseLocation2);
        assertEq(storedResponse2, response2, "Second response should be stored");

        // Verify rolling hash was updated sequentially
        bytes32 firstHash = keccak256(abi.encodePacked(bytes32(0), keccak256(response1)));
        bytes32 expectedRollingHash = keccak256(abi.encodePacked(firstHash, keccak256(response2)));
        bytes32 actualRollingHash =
            scopedCallable.readRollingHash(bridge1, IScopedCallable.RollingHashType.RESPONSES_IN);
        assertEq(actualRollingHash, expectedRollingHash, "Rolling hash should be updated sequentially");
    }

    function test_fillResponsesIn_RevertOnLengthMismatch() public {
        bytes[] memory bridges = new bytes[](1);
        bytes32[] memory requestHashes = new bytes32[](2); // Different length
        bytes[] memory responses = new bytes[](1);

        bridges[0] = bridge1;
        requestHashes[0] = requestHash1;
        requestHashes[1] = requestHash2;
        responses[0] = response1;

        vm.expectRevert(IScopedCallable.LengthMismatch.selector);
        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);
    }

    function test_fillResponsesIn_RevertOnResponseLengthMismatch() public {
        bytes[] memory bridges = new bytes[](1);
        bytes32[] memory requestHashes = new bytes32[](1);
        bytes[] memory responses = new bytes[](2); // Different length

        bridges[0] = bridge1;
        requestHashes[0] = requestHash1;
        responses[0] = response1;
        responses[1] = response2;

        vm.expectRevert(IScopedCallable.LengthMismatch.selector);
        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);
    }

    // ===================================================
    // readRollingHash Tests
    // ===================================================

    function test_readRollingHash_InitialState() public {
        bytes32 requestsOut = scopedCallable.readRollingHash(bridge1, IScopedCallable.RollingHashType.REQUESTS_OUT);
        bytes32 requestsIn = scopedCallable.readRollingHash(bridge1, IScopedCallable.RollingHashType.REQUESTS_IN);
        bytes32 responsesOut = scopedCallable.readRollingHash(bridge1, IScopedCallable.RollingHashType.RESPONSES_OUT);
        bytes32 responsesIn = scopedCallable.readRollingHash(bridge1, IScopedCallable.RollingHashType.RESPONSES_IN);

        assertEq(requestsOut, bytes32(0), "Initial requestsOut should be zero");
        assertEq(requestsIn, bytes32(0), "Initial requestsIn should be zero");
        assertEq(responsesOut, bytes32(0), "Initial responsesOut should be zero");
        assertEq(responsesIn, bytes32(0), "Initial responsesIn should be zero");
    }

    function test_readRollingHash_AfterUpdate() public {
        // Update a rolling hash
        bytes[] memory bridges = new bytes[](1);
        bytes32[] memory requestHashes = new bytes32[](1);
        bytes[] memory responses = new bytes[](1);

        bridges[0] = bridge1;
        requestHashes[0] = requestHash1;
        responses[0] = response1;

        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);

        // Read the updated hash
        bytes32 expectedHash = keccak256(abi.encodePacked(bytes32(0), keccak256(response1)));
        bytes32 actualHash = scopedCallable.readRollingHash(bridge1, IScopedCallable.RollingHashType.RESPONSES_IN);
        assertEq(actualHash, expectedHash, "Rolling hash should be updated after fillResponsesIn");
    }

    function test_readRollingHash_DifferentBridges() public {
        // Update hashes for different bridges
        bytes[] memory bridges = new bytes[](2);
        bytes32[] memory requestHashes = new bytes32[](2);
        bytes[] memory responses = new bytes[](2);

        bridges[0] = bridge1;
        bridges[1] = bridge2;
        requestHashes[0] = requestHash1;
        requestHashes[1] = requestHash2;
        responses[0] = response1;
        responses[1] = response2;

        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);

        // Verify each bridge has its own rolling hash
        bytes32 hash1 = scopedCallable.readRollingHash(bridge1, IScopedCallable.RollingHashType.RESPONSES_IN);
        bytes32 hash2 = scopedCallable.readRollingHash(bridge2, IScopedCallable.RollingHashType.RESPONSES_IN);

        assertEq(
            hash1, keccak256(abi.encodePacked(bytes32(0), keccak256(response1))), "Bridge1 should have correct hash"
        );
        assertEq(
            hash2, keccak256(abi.encodePacked(bytes32(0), keccak256(response2))), "Bridge2 should have correct hash"
        );
        assertTrue(hash1 != hash2, "Different bridges should have different hashes");
    }

    // ===================================================
    // readResponsesInboxValue Tests
    // ===================================================

    function test_readResponsesInboxValue_Empty() public {
        bytes32 responseLocation =
            keccak256(abi.encode(IScopedCallable.RollingHashType.RESPONSES_IN_VALUES, bridge1, requestHash1));
        bytes memory response = scopedCallable.readResponsesInboxValue(responseLocation);
        assertEq(response.length, 0, "Empty response should return empty bytes");
    }

    function test_readResponsesInboxValue_AfterFill() public {
        // Fill a response
        bytes[] memory bridges = new bytes[](1);
        bytes32[] memory requestHashes = new bytes32[](1);
        bytes[] memory responses = new bytes[](1);

        bridges[0] = bridge1;
        requestHashes[0] = requestHash1;
        responses[0] = response1;

        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);

        // Read the response
        bytes32 responseLocation =
            keccak256(abi.encode(IScopedCallable.RollingHashType.RESPONSES_IN_VALUES, bridge1, requestHash1));
        bytes memory storedResponse = scopedCallable.readResponsesInboxValue(responseLocation);
        assertEq(storedResponse, response1, "Response should be readable after fill");
    }

    function test_readResponsesInboxValue_MultipleResponses() public {
        // Fill multiple responses
        bytes[] memory bridges = new bytes[](2);
        bytes32[] memory requestHashes = new bytes32[](2);
        bytes[] memory responses = new bytes[](2);

        bridges[0] = bridge1;
        bridges[1] = bridge1; // Same bridge, different request
        requestHashes[0] = requestHash1;
        requestHashes[1] = requestHash2;
        responses[0] = response1;
        responses[1] = response2;

        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);

        // Read both responses
        bytes32 responseLocation1 =
            keccak256(abi.encode(IScopedCallable.RollingHashType.RESPONSES_IN_VALUES, bridge1, requestHash1));
        bytes memory storedResponse1 = scopedCallable.readResponsesInboxValue(responseLocation1);
        assertEq(storedResponse1, response1, "First response should be readable");

        bytes32 responseLocation2 =
            keccak256(abi.encode(IScopedCallable.RollingHashType.RESPONSES_IN_VALUES, bridge1, requestHash2));
        bytes memory storedResponse2 = scopedCallable.readResponsesInboxValue(responseLocation2);
        assertEq(storedResponse2, response2, "Second response should be readable");
    }

    // ===================================================
    // getRollingHashes Tests
    // ===================================================

    function test_getRollingHashes_InitialState() public {
        IScopedCallable.RollingHashes memory hashes = scopedCallable.getRollingHashes(bridge1);

        assertEq(hashes.requestsOut, bytes32(0), "Initial requestsOut should be zero");
        assertEq(hashes.requestsIn, bytes32(0), "Initial requestsIn should be zero");
        assertEq(hashes.responsesOut, bytes32(0), "Initial responsesOut should be zero");
        assertEq(hashes.responsesIn, bytes32(0), "Initial responsesIn should be zero");
    }

    function test_getRollingHashes_AfterUpdate() public {
        // Update responsesIn hash
        bytes[] memory bridges = new bytes[](1);
        bytes32[] memory requestHashes = new bytes32[](1);
        bytes[] memory responses = new bytes[](1);

        bridges[0] = bridge1;
        requestHashes[0] = requestHash1;
        responses[0] = response1;

        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);

        // Get all rolling hashes
        IScopedCallable.RollingHashes memory hashes = scopedCallable.getRollingHashes(bridge1);

        assertEq(hashes.requestsOut, bytes32(0), "requestsOut should still be zero");
        assertEq(hashes.requestsIn, bytes32(0), "requestsIn should still be zero");
        assertEq(hashes.responsesOut, bytes32(0), "responsesOut should still be zero");
        assertEq(
            hashes.responsesIn,
            keccak256(abi.encodePacked(bytes32(0), keccak256(response1))),
            "responsesIn should be updated"
        );
    }

    function test_getRollingHashes_DifferentBridges() public {
        // Update hashes for different bridges
        bytes[] memory bridges = new bytes[](2);
        bytes32[] memory requestHashes = new bytes32[](2);
        bytes[] memory responses = new bytes[](2);

        bridges[0] = bridge1;
        bridges[1] = bridge2;
        requestHashes[0] = requestHash1;
        requestHashes[1] = requestHash2;
        responses[0] = response1;
        responses[1] = response2;

        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);

        // Get hashes for both bridges
        IScopedCallable.RollingHashes memory hashes1 = scopedCallable.getRollingHashes(bridge1);
        IScopedCallable.RollingHashes memory hashes2 = scopedCallable.getRollingHashes(bridge2);

        assertEq(
            hashes1.responsesIn,
            keccak256(abi.encodePacked(bytes32(0), keccak256(response1))),
            "Bridge1 should have correct responsesIn"
        );
        assertEq(
            hashes2.responsesIn,
            keccak256(abi.encodePacked(bytes32(0), keccak256(response2))),
            "Bridge2 should have correct responsesIn"
        );
        assertTrue(hashes1.responsesIn != hashes2.responsesIn, "Different bridges should have different hashes");
    }

    // ===================================================
    // rollingHashesEqual Tests
    // ===================================================

    function test_rollingHashesEqual_InitialState() public {
        IScopedCallable.RollingHashes memory other = IScopedCallable.RollingHashes({
            requestsOut: bytes32(0),
            requestsIn: bytes32(0),
            responsesOut: bytes32(0),
            responsesIn: bytes32(0)
        });

        bool result = scopedCallable.rollingHashesEqual(bridge1, other);
        assertTrue(result, "Initial state hashes should be equal");
    }

    function test_rollingHashesEqual_NotEqual() public {
        // Update responsesIn hash
        bytes[] memory bridges = new bytes[](1);
        bytes32[] memory requestHashes = new bytes32[](1);
        bytes[] memory responses = new bytes[](1);

        bridges[0] = bridge1;
        requestHashes[0] = requestHash1;
        responses[0] = response1;

        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);

        // Compare with different hashes
        IScopedCallable.RollingHashes memory other = IScopedCallable.RollingHashes({
            requestsOut: bytes32(0),
            requestsIn: bytes32(0),
            responsesOut: bytes32(0),
            responsesIn: bytes32(0) // Different from updated hash
        });

        bool result = scopedCallable.rollingHashesEqual(bridge1, other);
        assertFalse(result, "Hashes should not be equal when different");
    }

    function test_rollingHashesEqual_Equal() public {
        // Update responsesIn hash
        bytes[] memory bridges = new bytes[](1);
        bytes32[] memory requestHashes = new bytes32[](1);
        bytes[] memory responses = new bytes[](1);

        bridges[0] = bridge1;
        requestHashes[0] = requestHash1;
        responses[0] = response1;

        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);

        // Get the actual hashes
        IScopedCallable.RollingHashes memory actualHashes = scopedCallable.getRollingHashes(bridge1);

        // Compare with matching hashes
        IScopedCallable.RollingHashes memory other = IScopedCallable.RollingHashes({
            requestsOut: actualHashes.requestsIn, // Swapped as per the logic
            requestsIn: actualHashes.requestsOut, // Swapped as per the logic
            responsesOut: actualHashes.responsesIn, // Swapped as per the logic
            responsesIn: actualHashes.responsesOut // Swapped as per the logic
        });

        bool result = scopedCallable.rollingHashesEqual(bridge1, other);
        assertTrue(result, "Hashes should be equal when matching");
    }

    // ===================================================
    // Edge Cases and Error Handling
    // ===================================================

    function test_fillResponsesIn_EmptyArrays() public {
        bytes[] memory bridges = new bytes[](0);
        bytes32[] memory requestHashes = new bytes32[](0);
        bytes[] memory responses = new bytes[](0);

        // Should not revert with empty arrays
        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);
    }

    function test_readRollingHash_NonExistentBridge() public {
        bytes memory nonExistentBridge = "non-existent-bridge";
        bytes32 hash = scopedCallable.readRollingHash(nonExistentBridge, IScopedCallable.RollingHashType.REQUESTS_OUT);
        assertEq(hash, bytes32(0), "Non-existent bridge should return zero hash");
    }

    function test_readResponsesInboxValue_NonExistentLocation() public {
        bytes32 nonExistentLocation = keccak256("non-existent-location");
        bytes memory response = scopedCallable.readResponsesInboxValue(nonExistentLocation);
        assertEq(response.length, 0, "Non-existent location should return empty bytes");
    }

    function test_getRollingHashes_NonExistentBridge() public {
        bytes memory nonExistentBridge = "non-existent-bridge";
        IScopedCallable.RollingHashes memory hashes = scopedCallable.getRollingHashes(nonExistentBridge);

        assertEq(hashes.requestsOut, bytes32(0), "Non-existent bridge should return zero hashes");
        assertEq(hashes.requestsIn, bytes32(0), "Non-existent bridge should return zero hashes");
        assertEq(hashes.responsesOut, bytes32(0), "Non-existent bridge should return zero hashes");
        assertEq(hashes.responsesIn, bytes32(0), "Non-existent bridge should return zero hashes");
    }

    // ===================================================
    // Integration Tests
    // ===================================================

    function test_CompleteWorkflow() public {
        // Step 1: Fill responses for multiple bridges
        bytes[] memory bridges = new bytes[](2);
        bytes32[] memory requestHashes = new bytes32[](2);
        bytes[] memory responses = new bytes[](2);

        bridges[0] = bridge1;
        bridges[1] = bridge2;
        requestHashes[0] = requestHash1;
        requestHashes[1] = requestHash2;
        responses[0] = response1;
        responses[1] = response2;

        scopedCallable.fillResponsesIn(bridges, requestHashes, responses);

        // Step 2: Verify responses are stored
        bytes32 responseLocation1 =
            keccak256(abi.encode(IScopedCallable.RollingHashType.RESPONSES_IN_VALUES, bridge1, requestHash1));
        bytes memory storedResponse1 = scopedCallable.readResponsesInboxValue(responseLocation1);
        assertEq(storedResponse1, response1, "Response1 should be stored correctly");

        bytes32 responseLocation2 =
            keccak256(abi.encode(IScopedCallable.RollingHashType.RESPONSES_IN_VALUES, bridge2, requestHash2));
        bytes memory storedResponse2 = scopedCallable.readResponsesInboxValue(responseLocation2);
        assertEq(storedResponse2, response2, "Response2 should be stored correctly");

        // Step 3: Verify rolling hashes are updated
        IScopedCallable.RollingHashes memory hashes1 = scopedCallable.getRollingHashes(bridge1);
        IScopedCallable.RollingHashes memory hashes2 = scopedCallable.getRollingHashes(bridge2);

        assertEq(
            hashes1.responsesIn,
            keccak256(abi.encodePacked(bytes32(0), keccak256(response1))),
            "Bridge1 responsesIn should be correct"
        );
        assertEq(
            hashes2.responsesIn,
            keccak256(abi.encodePacked(bytes32(0), keccak256(response2))),
            "Bridge2 responsesIn should be correct"
        );

        // Step 4: Test rolling hash equality
        IScopedCallable.RollingHashes memory other1 = IScopedCallable.RollingHashes({
            requestsOut: hashes1.requestsIn,
            requestsIn: hashes1.requestsOut,
            responsesOut: hashes1.responsesIn,
            responsesIn: hashes1.responsesOut
        });

        bool equality1 = scopedCallable.rollingHashesEqual(bridge1, other1);
        assertTrue(equality1, "Rolling hashes should be equal for bridge1");

        // Step 5: Add more responses and verify sequential updates
        bytes[] memory bridges3 = new bytes[](1);
        bytes32[] memory requestHashes3 = new bytes32[](1);
        bytes[] memory responses3 = new bytes[](1);

        bridges3[0] = bridge1;
        requestHashes3[0] = keccak256("request3");
        responses3[0] = "response3";

        scopedCallable.fillResponsesIn(bridges3, requestHashes3, responses3);

        // Verify the rolling hash was updated sequentially
        bytes32 firstHash = keccak256(abi.encodePacked(bytes32(0), keccak256(response1)));
        bytes32 expectedHash = keccak256(abi.encodePacked(firstHash, keccak256("response3")));
        bytes32 actualHash = scopedCallable.readRollingHash(bridge1, IScopedCallable.RollingHashType.RESPONSES_IN);
        assertEq(actualHash, expectedHash, "Rolling hash should be updated sequentially");
    }
}
