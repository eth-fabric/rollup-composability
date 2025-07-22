// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ICrossChainCaller} from "./ICrossChainCaller.sol";

contract CrossChainCaller is ICrossChainCaller {
    uint256 private _globalXCallNonce;
    uint256 private _chainId;

    /// @notice Rolling hash of all tx hashes sent to other chains.
    mapping(uint256 chainId_ => bytes32 rollingHash) private _transactionsOutbox;

    /// @notice Rolling hash of all tx hashes received from other chains.
    mapping(uint256 chainId_ => bytes32 rollingHash) private _transactionsInbox;

    /// @notice Rolling hash of result values from txs executed for other chains.
    mapping(uint256 chainId_ => bytes32 rollingHash) private _resultsOutbox;

    /// @notice Rolling hash of result values received from execution on other chains.
    mapping(uint256 chainId_ => bytes32 rollingHash) private _resultsInbox;

    /// @notice Ephemeral mapping of result values received from execution on other chains.
    mapping(uint256 chainId_ => mapping(bytes32 txHash => bytes result)) private _resultsInboxValues;

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
        _updateTransactionOutbox(targetChainId, txHash);

        // Emit a full log of the cross-chain call
        // This is how the sequencer generates the privileged transaction
        emit CrossChainCall(targetChainId, from, txn.to, nonce, txn.value, txn.gasLimit, txn.data);

        // Read prefilled result from inbox (already simulated by sequencer)
        return _readResultsInbox(targetChainId, txHash);
    }

    /// @inheritdoc ICrossChainCaller
    function xCallHandler(uint256 sourceChainId, address from, uint256 nonce, CrossCall calldata txn) external {
        // Reconstruct the expected transaction hash to maintain cross-chain accounting consistency
        bytes32 txHash = getTransactionHash(sourceChainId, _chainId, from, nonce, txn);

        // Update rolling inbox hash
        _updateTransactionsInbox(sourceChainId, txHash);

        // Execute local call
        (bool success, bytes memory result) = txn.to.call{gas: txn.gasLimit, value: txn.value}(txn.data);
        require(success, "Cross-chain call failed");

        // Update rolling result outbox hash
        _updateResultsOutbox(sourceChainId, keccak256(result));

        // Emit for sequencer to populate destination resultsInboxValues
        emit CrossChainCallExecuted(txHash, result);
    }


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

    function fillResultsInbox(uint256[] calldata chainIds, bytes32[] calldata txHashes, bytes[] calldata results)
        external
    {
        require(txHashes.length == results.length, "txHashes and results must have the same length");
        require(chainIds.length == txHashes.length, "chainIds and txHashes must have the same length");
        for (uint256 i = 0; i < txHashes.length; i++) {
            // Update values mapping
            _resultsInboxValues[chainIds[i]][txHashes[i]] = results[i];

            // Update rolling hash
            _resultsInbox[chainIds[i]] = keccak256(abi.encodePacked(_resultsInbox[chainIds[i]], keccak256(results[i])));
        }
    }

    // Internal functions

    // todo use ephemeral storage
    function _updateTransactionOutbox(uint256 chainId_, bytes32 txHash) internal {
        _transactionsOutbox[chainId_] = keccak256(abi.encodePacked(_transactionsOutbox[chainId_], txHash));
    }

    function _updateTransactionsInbox(uint256 chainId_, bytes32 txHash) internal {
        _transactionsInbox[chainId_] = keccak256(abi.encodePacked(_transactionsInbox[chainId_], txHash));
    }

    function _updateResultsOutbox(uint256 chainId_, bytes32 resultHash) internal {
        _resultsOutbox[chainId_] = keccak256(abi.encodePacked(_resultsOutbox[chainId_], resultHash));
    }

    function _updateResultsInbox(uint256 chainId_, bytes32 resultHash) internal {
        _resultsInbox[chainId_] = keccak256(abi.encodePacked(_resultsInbox[chainId_], resultHash));
    }

    function _readResultsInbox(uint256 chainId_, bytes32 txHash) internal view returns (bytes memory) {
        return _resultsInboxValues[chainId_][txHash];
    }

    // View functions
    function globalXCallNonce() external view returns (uint256) {
        return _globalXCallNonce;
    }

    function chainId() external view returns (uint256) {
        return _chainId;
    }

    function transactionOutbox(uint256 chainId_) external view returns (bytes32) {
        return _transactionsOutbox[chainId_];
    }

    function transactionInbox(uint256 chainId_) external view returns (bytes32) {
        return _transactionsInbox[chainId_];
    }

    function resultsOutbox(uint256 chainId_) external view returns (bytes32) {
        return _resultsOutbox[chainId_];
    }

    function resultsInbox(uint256 chainId_) external view returns (bytes32) {
        return _resultsInbox[chainId_];
    }

    function resultsInboxValues(uint256 chainId_, bytes32 txHash) external view returns (bytes memory) {
        return _resultsInboxValues[chainId_][txHash];
    }
}
