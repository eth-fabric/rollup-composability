// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ICrossChainCaller} from "./ICrossChainCaller.sol";
import {LibTransient} from "solady/utils/LibTransient.sol";

contract CrossChainCaller is ICrossChainCaller {
    uint256 private _globalXCallNonce;
    uint256 private _chainId;

    constructor(uint256 chainId_) {
        _chainId = chainId_;
    }

    /// @inheritdoc ICrossChainCaller
    function xCall(uint256 targetChainId, address from, CrossCall calldata txn) external returns (bytes memory) {
        // Increment and capture the nonce for this cross-chain message
        uint256 nonce = _globalXCallNonce++;

        // Unique and verifiable identifier
        bytes32 txHash = getTransactionHash(_chainId, targetChainId, from, nonce, txn);

        // Update rolling hash with txHash
        _updateRollingHash(targetChainId, txHash, MailboxType.TRANSACTIONS_OUTBOX);

        // Emit a full log of the cross-chain call
        // This is how the sequencer generates the privileged transaction
        emit CrossChainCall(targetChainId, from, txn.to, nonce, txn.value, txn.gasLimit, txn.data);

        // Read prefilled result from inbox (already simulated by sequencer)
        return _readResultInboxValue(targetChainId, txHash);
    }

    /// @inheritdoc ICrossChainCaller
    function xCallHandler(uint256 sourceChainId, address from, uint256 nonce, CrossCall calldata txn) external {
        // Reconstruct the expected transaction hash to maintain cross-chain accounting consistency
        bytes32 txHash = getTransactionHash(sourceChainId, _chainId, from, nonce, txn);

        // Update rolling inbox hash
        _updateRollingHash(sourceChainId, txHash, MailboxType.TRANSACTIONS_INBOX);

        // Execute local call
        (bool success, bytes memory result) = txn.to.call{gas: txn.gasLimit, value: txn.value}(txn.data);
        require(success, "Cross-chain call failed");

        // Update rolling result outbox hash
        _updateRollingHash(sourceChainId, keccak256(result), MailboxType.RESULTS_OUTBOX);

        // Emit for sequencer to populate destination resultsInboxValues
        emit CrossChainCallExecuted(txHash, result);
    }

    /// @notice Generates a unique transaction hash for a cross-chain call
    /// @param sourceChainId The chain ID where the cross-chain call originated from
    /// @param targetChainId The chain ID where the cross-chain call is handled
    /// @param from The address that initiated the cross-chain call on the source chain
    /// @param nonce The unique nonce for this cross-chain message
    /// @param txn Encapsulates target address, gas limit, value, and calldata
    function getTransactionHash(
        uint256 sourceChainId,
        uint256 targetChainId,
        address from,
        uint256 nonce,
        CrossCall calldata txn
    ) public pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                bytes32(sourceChainId),
                bytes32(targetChainId),
                bytes20(from),
                bytes20(txn.to),
                bytes32(nonce),
                bytes32(txn.value),
                bytes32(txn.gasLimit),
                bytes32(keccak256(txn.data))
            )
        );
    }

    /// @inheritdoc ICrossChainCaller
    function fillResultsInbox(uint256[] calldata chainIds, bytes32[] calldata txHashes, bytes[] calldata results)
        external
    {
        require(txHashes.length == results.length, "txHashes and results must have the same length");
        require(chainIds.length == txHashes.length, "chainIds and txHashes must have the same length");
        for (uint256 i = 0; i < txHashes.length; i++) {
            _updateResultInboxValue(chainIds[i], txHashes[i], results[i]);
            _updateRollingHash(chainIds[i], keccak256(results[i]), MailboxType.RESULTS_INBOX);
        }
    }

    // Updates and writes the rolling hash to transient storage
    function _updateRollingHash(uint256 chainId_, bytes32 newHash, MailboxType mailboxType) internal {
        // Each chainId has its own unique transient storage slot
        bytes32 key = keccak256(abi.encodePacked(mailboxType, chainId_));

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
    function _updateResultInboxValue(uint256 chainId_, bytes32 txHash, bytes memory result) internal {
        // Each chainId has its own unique transient storage slot
        bytes32 key = keccak256(abi.encode(MailboxType.RESULTS_INBOX_VALUES, chainId_, txHash));

        // Get a pointer to the transient storage
        LibTransient.TBytes storage p = LibTransient.tBytes(key);

        // Write the value to transient storage at pointer location
        LibTransient.setCompat(p, result);
    }

    // Reads bytes from transient storage
    function _readResultInboxValue(uint256 chainId_, bytes32 txHash) internal view returns (bytes memory) {
        // Each chainId has its own unique transient storage slot
        bytes32 key = keccak256(abi.encode(MailboxType.RESULTS_INBOX_VALUES, chainId_, txHash));

        // Get a pointer to the transient storage
        LibTransient.TBytes storage p = LibTransient.tBytes(key);

        // Read the value from transient storage at pointer location
        return LibTransient.getCompat(p);
    }

    // View functions
    /// @inheritdoc ICrossChainCaller
    function globalXCallNonce() external view returns (uint256) {
        return _globalXCallNonce;
    }

    /// @inheritdoc ICrossChainCaller
    function chainId() external view returns (uint256) {
        return _chainId;
    }

    /// @inheritdoc ICrossChainCaller
    function readRollingHash(uint256 chainId_, MailboxType mailboxType) external view returns (bytes32) {
        // Each chainId has its own unique transient storage slot
        bytes32 key = keccak256(abi.encodePacked(mailboxType, chainId_));

        // Get a pointer to the transient storage
        LibTransient.TBytes32 storage p = LibTransient.tBytes32(key);

        // Read the value from transient storage at pointer location
        return LibTransient.getCompat(p);
    }

    /// @inheritdoc ICrossChainCaller
    function readResultInboxValue(uint256 chainId_, bytes32 txHash) external view returns (bytes memory) {
        return _readResultInboxValue(chainId_, txHash);
    }
}
