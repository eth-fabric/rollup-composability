// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ISettlement {
    /// @notice The state root of the latest settled batch.
    /// @return The state root of the latest settled batch as a bytes32.
    function stateRoot(uint256 chainId) external view returns (bytes32);

    /// @notice The last block hash of the latest settled batch.
    /// @return The last block hash of the latest settled batch as a bytes32.
    function lastBlockHash() external view returns (bytes32);

    /// @notice A batch has been settled.
    /// @dev Event emitted when a batch is settled.
    event BatchSettled(uint256 indexed newStateRoot);

    /// @notice Settle a batch of L2 blocks.
    /// @dev The `newStateRoots` and `chainIds` arrays are assumed to be sorted ascending and mapped to each other.
    /// @param newStateRoots the new state roots for each chain.
    /// @param chainIds the chain IDs.
    /// @param tdxSignature the TDX signature over the publicly derived proof data.
    function settleBatch(bytes32[] calldata newStateRoots, uint256[] calldata chainIds, bytes calldata tdxSignature)
        external;
}
