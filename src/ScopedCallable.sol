// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IScopedCallable} from "./IScopedCallable.sol";
import {LibTransient} from "solady/utils/LibTransient.sol";

contract ScopedCallable is IScopedCallable {
    // =================================================== Setters ===================================================
    /// @inheritdoc IScopedCallable
    function fillResponsesIn(bytes[] calldata bridges, bytes32[] calldata requestHashes, bytes[] calldata responses)
        external
    {
        require(requestHashes.length == responses.length, "requestHashes and responses must have the same length");
        require(bridges.length == requestHashes.length, "bridges and requestHashes must have the same length");
        for (uint256 i = 0; i < requestHashes.length; i++) {
            _writeResponsesInboxValue(bridges[i], requestHashes[i], responses[i]);
            _updateRollingHash(bridges[i], keccak256(responses[i]), RollingHashType.RESPONSES_IN);
        }
    }

    // =================================================== Getters ===================================================
    /// @inheritdoc IScopedCallable
    function rollingHashesEqual(bytes calldata bridge, RollingHashes memory other) external view returns (bool) {
        return _rollingHashesEqual(bridge, other);
    }

    /// @inheritdoc IScopedCallable
    function readRollingHash(bytes calldata bridge, RollingHashType rollingHashType) external view returns (bytes32) {
        return _readRollingHash(bridge, rollingHashType);
    }

    /// @inheritdoc IScopedCallable
    function readResponsesInboxValue(bytes32 responseLocation) external view returns (bytes memory) {
        return _readResponsesInboxValue(responseLocation);
    }

    /// @inheritdoc IScopedCallable
    function getRollingHashes(bytes calldata bridge) external view returns (RollingHashes memory) {
        return _getRollingHashes(bridge);
    }

    // ================================================== Internal ===================================================
    function _rollingHashesEqual(bytes calldata bridge, RollingHashes memory other) internal view returns (bool) {
        RollingHashes memory rollingHashes = _getRollingHashes(bridge);

        return rollingHashes.requestsOut == other.requestsIn && rollingHashes.requestsIn == other.requestsOut
            && rollingHashes.responsesOut == other.responsesIn && rollingHashes.responsesIn == other.responsesOut;
    }

    function _getRollingHashes(bytes calldata bridge) internal view returns (RollingHashes memory) {
        return RollingHashes({
            requestsOut: _readRollingHash(bridge, RollingHashType.REQUESTS_OUT),
            requestsIn: _readRollingHash(bridge, RollingHashType.REQUESTS_IN),
            responsesOut: _readRollingHash(bridge, RollingHashType.RESPONSES_OUT),
            responsesIn: _readRollingHash(bridge, RollingHashType.RESPONSES_IN)
        });
    }

    function _readRollingHash(bytes calldata bridge, RollingHashType rollingHashType) internal view returns (bytes32) {
        // Each chainId has its own unique transient storage slot
        bytes32 key = keccak256(abi.encodePacked(rollingHashType, bridge));

        // Get a pointer to the transient storage
        LibTransient.TBytes32 storage p = LibTransient.tBytes32(key);

        // Read the value from transient storage at pointer location
        return LibTransient.getCompat(p);
    }

    // Updates and writes the rolling hash to transient storage
    // Note the getCompat function does not use transient storage on an L2s
    function _updateRollingHash(bytes memory bridge, bytes32 newHash, RollingHashType rollingHashType) internal {
        // Each chainId has its own unique transient storage slot
        bytes32 key = keccak256(abi.encodePacked(rollingHashType, bridge));

        // Get a pointer to the transient storage
        LibTransient.TBytes32 storage p = LibTransient.tBytes32(key);

        // Read the value from transient storage at pointer location
        bytes32 rollingHash = LibTransient.getCompat(p);

        // Update rolling hash
        bytes32 value = keccak256(abi.encodePacked(rollingHash, newHash));

        // Write the value to transient storage at pointer location
        LibTransient.setCompat(p, value);
    }

    function _calcStorageKey(RollingHashType rollingHashType, bytes memory bridge, bytes32 requestHash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(rollingHashType, bridge, requestHash));
    }

    // Writes bytes to transient storage
    function _writeResponsesInboxValue(bytes calldata bridge, bytes32 requestHash, bytes memory result) internal {
        // Each chainId has its own unique transient storage slot
        bytes32 responseLocation = _calcStorageKey(RollingHashType.RESPONSES_IN_VALUES, bridge, requestHash);

        // Get a pointer to the transient storage
        LibTransient.TBytes storage p = LibTransient.tBytes(responseLocation);

        // Write the value to transient storage at pointer location
        LibTransient.setCompat(p, result);
    }

    // Reads bytes from transient storage
    function _readResponsesInboxValue(bytes32 responseLocation) internal view returns (bytes memory) {
        // Get a pointer to the transient storage
        LibTransient.TBytes storage p = LibTransient.tBytes(responseLocation);

        // Read the value from transient storage at pointer location
        return LibTransient.getCompat(p);
    }
}
