// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IScopedCallable {
    struct ScopedRequest {
        address to;
        uint256 value;
        uint256 gasLimit;
        bytes data;
    }

    struct RollingHashes {
        bytes32 requestsOut;
        bytes32 requestsIn;
        bytes32 responsesOut;
        bytes32 responsesIn;
    }

    enum RollingHashType {
        REQUESTS_OUT,
        REQUESTS_IN,
        RESPONSES_OUT,
        RESPONSES_IN,
        RESPONSES_IN_VALUES
    }

    event ScopedCall(
        uint256 indexed targetChainId,
        address indexed from,
        address indexed to,
        uint256 nonce,
        uint256 value,
        uint256 gasLimit,
        bytes data
    );

    error UnsupportedChain();

    event ScopedCallExecuted(bytes32 indexed requestHash, bytes response);

    /// @notice Initiates a synchronous cross-chain call.
    /// @dev Emits an event, updates a nonce, and updates the requestsOutHash.
    ///      Reads the result from the responsesIn array (pre-filled by the sequencer).
    /// @param targetChainId The ID of the chain the `ScopedRequest` will execute on.
    /// @param from The address that initiated the cross-chain call on the source chain.
    /// @param request Encoded function call for the destination chain.
    /// @return response The result bytes returned from the responsesIn array.
    function scopedCall(uint256 targetChainId, address from, ScopedRequest calldata request)
        external
        payable
        returns (bytes memory response);

    /// @notice Executes a cross-chain call.
    /// @dev Called by the sequencer. Updates requestsInHash, emits an event, and updates responsesOutHash.
    /// @param sourceChainId The ID of the chain the `ScopedRequest` was initiated from.
    /// @param from The sender address on the origin chain.
    /// @param nonce A unique nonce for deduplication.
    /// @param request Encoded call to execute locally.
    function handleScopedCall(uint256 sourceChainId, address from, uint256 nonce, ScopedRequest calldata request)
        external;

    /// @notice Fills the responses inbox with pre-simulated responses for cross-chain calls
    /// @dev This is called by the sequencer to populate responses before scopedCall is executed
    /// @param chainIds Chain IDs corresponding to each response
    /// @param txHashes Hashes of the transactions that generated the responses
    /// @param responses Response bytes for each executed transaction
    function fillResponsesIn(uint256[] calldata chainIds, bytes32[] calldata txHashes, bytes[] calldata responses)
        external;

    /// @notice Compares the rolling hashes of two chains
    /// @param chainId The chain ID to compare the rolling hashes of
    /// @param destinationRollingHashes The other chain's rolling hashes to compare to
    /// @return Whether the rolling hashes are equal
    function rollingHashesEqual(uint256 chainId, RollingHashes memory destinationRollingHashes)
        external
        view
        returns (bool);

    /// @notice Generates a unique transaction hash for a cross-chain call
    /// @param sourceChainId The chain ID where the cross-chain call originated from
    /// @param targetChainId The chain ID where the cross-chain call is handled
    /// @param from The address that initiated the cross-chain call on the source chain
    /// @param nonce The unique nonce for this cross-chain message
    /// @param request Encapsulates target address, gas limit, value, and calldata
    function getTransactionHash(
        uint256 sourceChainId,
        uint256 targetChainId,
        address from,
        uint256 nonce,
        ScopedRequest memory request
    ) external pure returns (bytes32);

    /// @notice Returns the current global nonce used for cross-chain calls
    /// @return The current nonce value
    function globalScopedCallNonce() external view returns (uint256);

    /// @notice Returns the chain ID this contract was deployed on
    /// @return The chain ID value
    function chainId() external view returns (uint256);

    /// @notice Returns whether a chain is supported
    /// @param chainId_ The chain ID to check
    /// @return Whether the chain is supported
    function chainSupported(uint256 chainId_) external view returns (bool);

    /// @notice Reads the current rolling hashes for a given chain ID
    /// @param chainId_ The chain ID to read the rolling hashes for
    /// @return The rolling hashes for the given chain ID
    function getRollingHashes(uint256 chainId_) external view returns (RollingHashes memory);

    /// @notice Reads the current rolling hash for a given chain ID and mailbox type
    /// @param chainId_ The chain ID to read the rolling hash for
    /// @param rollingHashType The type of rolling hash to read from (requests or responses, in or out)
    /// @return The current rolling hash value
    function readRollingHash(uint256 chainId_, RollingHashType rollingHashType) external view returns (bytes32);

    /// @notice Reads a specific response value from the responses inbox
    /// @param chainId_ The chain ID to read the response from
    /// @param requestHash The request hash corresponding to the response
    /// @return The response bytes stored for the given transaction
    function readResponsesInboxValue(uint256 chainId_, bytes32 requestHash) external view returns (bytes memory);
}
