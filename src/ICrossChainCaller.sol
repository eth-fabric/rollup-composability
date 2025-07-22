// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICrossChainCaller {
    struct CrossCall {
        address to;
        uint256 value;
        uint256 gasLimit;
        bytes data;
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

    function fillResultsInbox(uint256[] calldata chainIds, bytes32[] calldata txHashes, bytes[] calldata results) external;

    function globalXCallNonce() external view returns (uint256);

    function chainId() external view returns (uint256);

    function transactionOutbox(uint256 chainId_) external view returns (bytes32);

    function transactionInbox(uint256 chainId_) external view returns (bytes32);

    function resultsOutbox(uint256 chainId_) external view returns (bytes32);

    function resultsInbox(uint256 chainId_) external view returns (bytes32);

    function resultsInboxValues(uint256 chainId_, bytes32 txHash) external view returns (bytes memory);
}
