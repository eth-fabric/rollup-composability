// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICrossChainCaller {
    struct CrossCall {
        address to;
        uint256 value;
        uint256 gasLimit;
        bytes data;
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

    event CrossChainCallExecuted(bytes32 indexed txHash, bytes result);

    /// @notice Performs a synchronous cross-chain call to a contract on another chain.
    /// @dev This function simulates a synchronous cross-chain call using an optimistic "mailbox" model.
    ///      In simulation mode, the sequencer intercepts and executes the remote call on the target rollup,
    ///      then returns the result directly to the caller without modifying the actual transactionsInbox state.
    ///      In execution mode, the result is read from a pre-filled transactionsInbox, ensuring determinism and verifiability.
    /// @param targetChainId Target chain ID to send the cross-chain call to
    /// @param from The address that initiated the cross-chain call on the source chain
    /// @param txn Encapsulates target address, gas limit, value, and calldata
    /// @return The result bytes returned by the cross-chain call
    function xCall(uint256 targetChainId, address from, CrossCall calldata txn) external returns (bytes memory);

    /// @notice Executes a transaction received via xCall from a source chain.
    /// @dev This is invoked only by the sequencer as part of rollup block production.
    ///      It records the txHash in the transactionsInbox and appends the result hash to the resultsOutbox.
    /// @param sourceChainId The chain ID where the cross-chain call originated from
    /// @param from The address that initiated the cross-chain call on the source chain
    /// @param nonce The unique nonce for this cross-chain message
    /// @param txn Encapsulates target address, gas limit, value, and calldata
    function xCallHandler(uint256 sourceChainId, address from, uint256 nonce, CrossCall calldata txn) external;

    /// @notice Fills the results inbox with pre-simulated results for cross-chain calls
    /// @dev This is called by the sequencer to populate results before xCall is executed
    /// @param chainIds Array of chain IDs corresponding to each result
    /// @param txHashes Array of transaction hashes corresponding to each result
    /// @param results Array of result bytes for each transaction
    function fillResultsInbox(uint256[] calldata chainIds, bytes32[] calldata txHashes, bytes[] calldata results)
        external;

    /// @notice Returns the current global nonce used for cross-chain calls
    /// @return The current nonce value
    function globalXCallNonce() external view returns (uint256);

    /// @notice Returns the chain ID this contract was deployed on
    /// @return The chain ID value
    function chainId() external view returns (uint256);

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
