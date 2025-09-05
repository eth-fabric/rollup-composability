// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IScopedCallable} from "./IScopedCallable.sol";
import {ITDXVerifier} from "./ITDXVerifier.sol";

contract Settlement {
    /// @notice The state root of the latest settled batch.
    mapping(bytes32 bridgeHash => bytes32 stateRoot) internal _stateRoots;

    /// @notice The last block hash of the latest settled batch.
    bytes32 internal _lastBlockHash;

    /// @notice Address used to avoid the verification process.
    /// @dev Used only in dev mode.
    address public constant DEV_MODE = address(0xAA);

    IScopedCallable internal _sharedBridge;
    address internal _sequencer;
    address internal _tdxVerifier;

    modifier onlySequencer() {
        require(msg.sender == _sequencer, "Settlement: caller is not the sequencer");
        _;
    }

    constructor(address sharedBridge_, address sequencer_, address tdxVerifier_) {
        _sharedBridge = IScopedCallable(sharedBridge_);
        _tdxVerifier = tdxVerifier_;
        _sequencer = sequencer_;
    }

    function settleBatch(bytes32[] calldata newStateRoots, bytes[] calldata bridges, bytes calldata tdxSignature)
        external
        onlySequencer
    {
        require(newStateRoots.length == bridges.length, "Settlement: input length mismatch");

        // Get the public proof inputs
        bytes memory publicData = _getPublicData(newStateRoots, bridges);

        // Verify the TDX proof
        if (_tdxVerifier != DEV_MODE) {
            // If the verification fails, it will revert.
            ITDXVerifier(_tdxVerifier).verify(publicData, tdxSignature);
        }

        // Update the last block hash
        _lastBlockHash = blockhash(block.number);

        // Update the state root for each chain
        for (uint256 i = 0; i < bridges.length; i++) {
            _stateRoots[keccak256(bridges[i])] = newStateRoots[i];
        }
    }

    // View functions

    function stateRoot(bytes calldata bridge) external view returns (bytes32) {
        return _stateRoots[keccak256(bridge)];
    }

    function lastBlockHash() external view returns (bytes32) {
        return _lastBlockHash;
    }

    // Internal functions
    function _getBlobHash() internal view returns (bytes32) {
        // todo
        return blobhash(0);
    }

    /// @notice Get the public data for the settlement.
    /// @dev The `newStateRoots` and `bridges` arrays are assumed to be sorted ascending and mapped to each other.
    /// @param newStateRoots The new state roots for each chain.
    /// @param bridges The bridges for each chain.
    /// @return The public settlement data.
    function _getPublicData(bytes32[] calldata newStateRoots, bytes[] calldata bridges)
        internal
        view
        returns (bytes memory)
    {
        bytes memory publicData;

        // old and new state root pairs
        for (uint256 i = 0; i < bridges.length; i++) {
            publicData = bytes.concat(publicData, _stateRoots[keccak256(bridges[i])], newStateRoots[i]);
        }

        // blobhash
        publicData = bytes.concat(publicData, _getBlobHash());

        // last block hash
        publicData = bytes.concat(publicData, _lastBlockHash);

        // get shared bridge's rolling hashes for each chain
        for (uint256 i = 0; i < bridges.length; i++) {
            IScopedCallable.RollingHashes memory rollingHashes = _sharedBridge.getRollingHashes(bridges[i]);
            publicData = bytes.concat(
                publicData,
                bytes32(rollingHashes.requestsIn),
                bytes32(rollingHashes.requestsOut),
                bytes32(rollingHashes.responsesIn),
                bytes32(rollingHashes.responsesOut)
            );
        }
        return publicData;
    }
}
