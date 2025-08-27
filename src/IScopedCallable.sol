// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IScopedCallable {
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

    error LengthMismatch();

    /// @notice Fills the responses inbox with pre-simulated responses for cross-chain calls
    /// @dev This is called by the sequencer to populate responses before scopedCall is executed
    /// @param bridges Bridges corresponding to each response
    /// @param requestHashes Hashes of the transactions that generated the responses
    /// @param responses Response bytes for each executed transaction
    function fillResponsesIn(bytes[] calldata bridges, bytes32[] calldata requestHashes, bytes[] calldata responses)
        external;

    /// @notice Compares the rolling hashes of two chains
    /// @param bridge The bridge to compare the rolling hashes of
    /// @param destinationRollingHashes The other chain's rolling hashes to compare to
    /// @return Whether the rolling hashes are equal
    function rollingHashesEqual(bytes calldata bridge, RollingHashes memory destinationRollingHashes)
        external
        view
        returns (bool);

    /// @notice Reads the current rolling hashes for a given chain ID
    /// @param bridge The bridge to read the rolling hashes for
    /// @return The rolling hashes for the given chain ID
    function getRollingHashes(bytes calldata bridge) external view returns (RollingHashes memory);

    /// @notice Reads the current rolling hash for a given chain ID and mailbox type
    /// @param bridge The bridge to read the rolling hash for
    /// @param rollingHashType The type of rolling hash to read from (requests or responses, in or out)
    /// @return The current rolling hash value
    function readRollingHash(bytes calldata bridge, RollingHashType rollingHashType) external view returns (bytes32);

    /// @notice Reads a specific response value from the responses inbox
    /// @param responseLocation The memory location of the response in the responses inbox
    /// @return The response bytes stored for the given transaction
    function readResponsesInboxValue(bytes32 responseLocation) external view returns (bytes memory);
}
