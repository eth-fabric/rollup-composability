// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICrossChainCaller {
    struct CrossCall {
        address to;
        uint256 value;
        uint256 gasLimit;
        bytes data;
    }

    struct MailboxCommitments {
        bytes32 transactionsOutbox;
        bytes32 transactionsInbox;
        bytes32 resultsOutbox;
        bytes32 resultsInbox;
    }

    enum MailboxType {
        TRANSACTIONS_OUTBOX,
        TRANSACTIONS_INBOX,
        RESULTS_OUTBOX,
        RESULTS_INBOX,
        RESULTS_INBOX_VALUES
    }

    event CrossChainCall(
        uint256 indexed targetChainId,
        address indexed from,
        address indexed to,
        uint256 nonce,
        uint256 value,
        uint256 gasLimit,
        bytes data
    );

    error UnsupportedChain();

    event CrossChainCallExecuted(bytes32 indexed txHash, bytes result);

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
        CrossCall memory txn
    ) external pure returns (bytes32);

    /// @notice Fills the results inbox with pre-simulated results for cross-chain calls
    /// @dev This is called by the sequencer to populate results before xCall is executed
    /// @param chainIds Chain IDs corresponding to each result
    /// @param txHashes Hashes of the transactions that generated the results
    /// @param results Result bytes for each executed transaction
    function fillResultsInbox(uint256[] calldata chainIds, bytes32[] calldata txHashes, bytes[] calldata results)
        external;

    /// @notice Returns the current global nonce used for cross-chain calls
    /// @return The current nonce value
    function globalXCallNonce() external view returns (uint256);

    /// @notice Returns the chain ID this contract was deployed on
    /// @return The chain ID value
    function chainId() external view returns (uint256);

    /// @notice Returns whether a chain is supported
    /// @param chainId_ The chain ID to check
    /// @return Whether the chain is supported
    function chainSupported(uint256 chainId_) external view returns (bool);

    /// @notice Reads the current rolling hashes for a given chain ID
    /// @param chainId_ The chain ID to read the rolling hash for
    /// @return The mailbox commitments for the given chain ID
    function readMailboxes(uint256 chainId_) external view returns (MailboxCommitments memory);

    /// @notice Reads the current rolling hash for a given chain ID and mailbox type
    /// @param chainId_ The chain ID to read the rolling hash for
    /// @param mailboxType The type of mailbox to read from (transactions or results, inbox or outbox)
    /// @return The current rolling hash value
    function readRollingHash(uint256 chainId_, MailboxType mailboxType) external view returns (bytes32);

    /// @notice Reads a specific result value from the results inbox
    /// @param chainId_ The chain ID to read the result from
    /// @param txHash The transaction hash corresponding to the result
    /// @return The result bytes stored for the given transaction
    function readResultInboxValue(uint256 chainId_, bytes32 txHash) external view returns (bytes memory);
}
