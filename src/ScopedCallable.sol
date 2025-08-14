// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IScopedCallable} from "./IScopedCallable.sol";
import {LibTransient} from "solady/utils/LibTransient.sol";

contract ScopedCallable is IScopedCallable {
    uint256 internal _globalScopedCallNonce;
    uint256 internal _chainId;

    mapping(uint256 chainId => bool supported) internal _supportedChains;

    constructor(uint256 chainId_) {
        _chainId = chainId_;
    }

    /// @inheritdoc IScopedCallable
    function scopedCall(uint256 targetChainId, address from, ScopedRequest memory request)
        external
        payable
        virtual
        returns (bytes memory response)
    {
        return _scopedCall(targetChainId, from, request);
    }

    /// @inheritdoc IScopedCallable
    function handleScopedCall(uint256 sourceChainId, address from, uint256 nonce, ScopedRequest memory request)
        external
        virtual
    {
        return _handleScopedCall(sourceChainId, from, nonce, request);
    }

    /// @inheritdoc IScopedCallable
    function fillResponsesIn(uint256[] calldata chainIds, bytes32[] calldata requestHashes, bytes[] calldata responses)
        external
    {
        require(requestHashes.length == responses.length, "requestHashes and responses must have the same length");
        require(chainIds.length == requestHashes.length, "chainIds and requestHashes must have the same length");
        for (uint256 i = 0; i < requestHashes.length; i++) {
            _updateResponsesInboxValue(chainIds[i], requestHashes[i], responses[i]);
            _updateRollingHash(chainIds[i], keccak256(responses[i]), RollingHashType.RESPONSES_IN);
        }
    }

    // View functions

    /// @inheritdoc IScopedCallable
    function rollingHashesEqual(uint256 chainId_, RollingHashes memory other) external view returns (bool) {
        return _rollingHashesEqual(chainId_, other);
    }

    /// @inheritdoc IScopedCallable
    function readRollingHash(uint256 chainId_, RollingHashType rollingHashType) external view returns (bytes32) {
        return _readRollingHash(chainId_, rollingHashType);
    }

    /// @inheritdoc IScopedCallable
    function readResponsesInboxValue(uint256 chainId_, bytes32 requestHash) external view returns (bytes memory) {
        return _readResponsesInboxValue(chainId_, requestHash);
    }

    /// @inheritdoc IScopedCallable
    function getRollingHashes(uint256 chainId_) external view returns (RollingHashes memory) {
        return _getRollingHashes(chainId_);
    }

    /// @inheritdoc IScopedCallable
    function getTransactionHash(
        uint256 sourceChainId,
        uint256 targetChainId,
        address from,
        uint256 nonce,
        ScopedRequest memory request
    ) external pure returns (bytes32) {
        return _getTransactionHash(sourceChainId, targetChainId, from, nonce, request);
    }
    /// @inheritdoc IScopedCallable

    function globalScopedCallNonce() external view returns (uint256) {
        return _globalScopedCallNonce;
    }

    /// @inheritdoc IScopedCallable
    function chainId() external view returns (uint256) {
        return _chainId;
    }

    /// @inheritdoc IScopedCallable
    function chainSupported(uint256 chainId_) external view returns (bool) {
        return _chainSupported(chainId_);
    }

    // Internal functions

    /// @notice Performs a synchronous cross-chain call to a contract on another chain.
    /// @dev This function simulates a synchronous cross-chain call using an optimistic "mailbox" model.
    ///      In simulation mode, the sequencer intercepts and executes the remote call on the target rollup,
    ///      then returns the result directly to the caller without modifying the actual transactionsInbox state.
    ///      In execution mode, the result is read from a pre-filled transactionsInbox, ensuring determinism and verifiability.
    /// @param targetChainId Target chain ID to send the cross-chain call to
    /// @param from The address that initiated the cross-chain call on the source chain
    /// @param request Encapsulates target address, gas limit, value, and calldata
    /// @return response The result bytes returned by the cross-chain call
    function _scopedCall(uint256 targetChainId, address from, ScopedRequest memory request)
        internal
        returns (bytes memory response)
    {
        // Increment and capture the nonce for this cross-chain message
        uint256 nonce = _globalScopedCallNonce++;

        // Unique and verifiable identifier
        bytes32 requestHash = _getTransactionHash(_chainId, targetChainId, from, nonce, request);

        // Update rolling hash with requestHash
        _updateRollingHash(targetChainId, requestHash, RollingHashType.REQUESTS_OUT);

        // Emit a full log of the cross-chain call
        // This is how the sequencer generates the privileged transaction
        emit ScopedCall(targetChainId, from, request.to, nonce, request.value, request.gasLimit, request.data);

        // Read prefilled result from inbox (already simulated by sequencer)
        response = _readResponsesInboxValue(targetChainId, requestHash);
    }

    /// @notice Executes a transaction received via scopedCall from a source chain.
    /// @dev This is invoked only by the sequencer as part of rollup block production.
    ///      It records the requestHash in the requestsInbox and appends the result hash to the responsesOutbox.
    /// @param sourceChainId The chain ID where the cross-chain call originated from
    /// @param from The address that initiated the cross-chain call on the source chain
    /// @param nonce The unique nonce for this cross-chain message
    /// @param request Encapsulates target address, gas limit, value, and calldata
    function _handleScopedCall(uint256 sourceChainId, address from, uint256 nonce, ScopedRequest memory request)
        internal
    {
        // Reconstruct the expected transaction hash to maintain cross-chain accounting consistency
        bytes32 requestHash = _getTransactionHash(sourceChainId, _chainId, from, nonce, request);

        // Update rolling inbox hash
        _updateRollingHash(sourceChainId, requestHash, RollingHashType.REQUESTS_IN);

        // Execute local call
        (bool success, bytes memory result) = request.to.call{gas: request.gasLimit, value: request.value}(request.data);
        require(success, "Cross-chain call failed");

        // Update rolling result outbox hash
        _updateRollingHash(sourceChainId, keccak256(result), RollingHashType.RESPONSES_OUT);

        // Emit for sequencer to populate source-chain's responsesInboxValues
        emit ScopedCallExecuted(requestHash, result);
    }

    function _rollingHashesEqual(uint256 chainId_, RollingHashes memory other) internal view returns (bool) {
        RollingHashes memory rollingHashes = _getRollingHashes(chainId_);

        return rollingHashes.requestsOut == other.requestsIn && rollingHashes.requestsIn == other.requestsOut
            && rollingHashes.responsesOut == other.responsesIn && rollingHashes.responsesIn == other.responsesOut;
    }

    function _getRollingHashes(uint256 chainId_) internal view returns (RollingHashes memory) {
        return RollingHashes({
            requestsOut: _readRollingHash(chainId_, RollingHashType.REQUESTS_OUT),
            requestsIn: _readRollingHash(chainId_, RollingHashType.REQUESTS_IN),
            responsesOut: _readRollingHash(chainId_, RollingHashType.RESPONSES_OUT),
            responsesIn: _readRollingHash(chainId_, RollingHashType.RESPONSES_IN)
        });
    }

    function _readRollingHash(uint256 chainId_, RollingHashType rollingHashType) internal view returns (bytes32) {
        // Each chainId has its own unique transient storage slot
        bytes32 key = keccak256(abi.encodePacked(rollingHashType, chainId_));

        // Get a pointer to the transient storage
        LibTransient.TBytes32 storage p = LibTransient.tBytes32(key);

        // Read the value from transient storage at pointer location
        return LibTransient.getCompat(p);
    }

    function _getTransactionHash(
        uint256 sourceChainId,
        uint256 targetChainId,
        address from,
        uint256 nonce,
        ScopedRequest memory request
    ) public pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                bytes32(sourceChainId),
                bytes32(targetChainId),
                bytes20(from),
                bytes20(request.to),
                bytes32(nonce),
                bytes32(request.value),
                bytes32(request.gasLimit),
                bytes32(keccak256(request.data))
            )
        );
    }

    // Updates and writes the rolling hash to transient storage
    // Note the getCompat function does not use transient storage on an L2s
    function _updateRollingHash(uint256 chainId_, bytes32 newHash, RollingHashType rollingHashType) internal {
        // Each chainId has its own unique transient storage slot
        bytes32 key = keccak256(abi.encodePacked(rollingHashType, chainId_));

        // Get a pointer to the transient storage
        LibTransient.TBytes32 storage p = LibTransient.tBytes32(key);

        // Read the value from transient storage at pointer location
        bytes32 rollingHash = LibTransient.getCompat(p);

        // Update rolling hash
        bytes32 value = keccak256(abi.encodePacked(rollingHash, newHash));

        // Write the value to transient storage at pointer location
        LibTransient.setCompat(p, value);
    }

    // Writes bytes to transient storage
    function _updateResponsesInboxValue(uint256 chainId_, bytes32 requestHash, bytes memory result) internal {
        // Each chainId has its own unique transient storage slot
        bytes32 key = keccak256(abi.encode(RollingHashType.RESPONSES_IN_VALUES, chainId_, requestHash));

        // Get a pointer to the transient storage
        LibTransient.TBytes storage p = LibTransient.tBytes(key);

        // Write the value to transient storage at pointer location
        LibTransient.setCompat(p, result);
    }

    // Reads bytes from transient storage
    function _readResponsesInboxValue(uint256 chainId_, bytes32 requestHash) internal view returns (bytes memory) {
        // Each chainId has its own unique transient storage slot
        bytes32 key = keccak256(abi.encode(RollingHashType.RESPONSES_IN_VALUES, chainId_, requestHash));

        // Get a pointer to the transient storage
        LibTransient.TBytes storage p = LibTransient.tBytes(key);

        // Read the value from transient storage at pointer location
        return LibTransient.getCompat(p);
    }

    function _chainSupported(uint256 chainId_) internal view returns (bool) {
        return _supportedChains[chainId_];
    }

    function _editSupportedChain(uint256 chainId_, bool supported) internal {
        _supportedChains[chainId_] = supported;
    }
}
