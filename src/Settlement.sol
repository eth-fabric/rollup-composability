// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.13;

// import "./ISettlement.sol";
// import {IScopedCallable} from "./IScopedCallable.sol";
// import {ISharedBridge} from "./ISharedBridge.sol";
// import {ITDXVerifier} from "./ITDXVerifier.sol";

// contract Settlement is ISettlement {
//     /// @notice The state root of the latest settled batch.
//     mapping(uint256 chainId => bytes32 stateRoot) internal _stateRoots;

//     /// @notice The last block hash of the latest settled batch.
//     bytes32 internal _lastBlockHash;

//     /// @notice Address used to avoid the verification process.
//     /// @dev Used only in dev mode.
//     address public constant DEV_MODE = address(0xAA);

//     IScopedCallable internal _sharedBridge;
//     address internal _sequencer;
//     address internal _tdxVerifier;

//     modifier onlySequencer() {
//         require(msg.sender == _sequencer, "Settlement: caller is not the sequencer");
//         _;
//     }

//     constructor(address sharedBridge_, address sequencer_, address tdxVerifier_) {
//         _sharedBridge = IScopedCallable(sharedBridge_);
//         _tdxVerifier = tdxVerifier_;
//         _sequencer = sequencer_;
//     }

//     /// @inheritdoc ISettlement
//     function settleBatch(bytes32[] calldata newStateRoots, uint256[] calldata chainIds, bytes calldata tdxSignature)
//         external
//         override
//         onlySequencer
//     {
//         require(newStateRoots.length == chainIds.length, "Settlement: input length mismatch");

//         // Get the public proof inputs
//         bytes memory publicData = _getPublicData(newStateRoots, chainIds);

//         // Verify the TDX proof
//         if (_tdxVerifier != DEV_MODE) {
//             // If the verification fails, it will revert.
//             ITDXVerifier(_tdxVerifier).verify(publicData, tdxSignature);
//         }

//         // Update the last block hash
//         _lastBlockHash = blockhash(block.number);

//         // Update the state root for each chain
//         for (uint256 i = 0; i < chainIds.length; i++) {
//             _stateRoots[chainIds[i]] = newStateRoots[i];
//         }
//     }

//     // View functions

//     function stateRoot(uint256 chainId) external view returns (bytes32) {
//         return _stateRoots[chainId];
//     }

//     function lastBlockHash() external view returns (bytes32) {
//         return _lastBlockHash;
//     }

//     // Internal functions
//     function _getBlobHash() internal view returns (bytes32) {
//         // todo
//         return blobhash(0);
//     }

//     /// @notice Get the public data for the settlement.
//     /// @dev The `newStateRoots` and `chainIds` arrays are assumed to be sorted ascending and mapped to each other.
//     /// @param newStateRoots The new state roots for each chain.
//     /// @param chainIds The chain IDs.
//     /// @return The public settlement data.
//     function _getPublicData(bytes32[] calldata newStateRoots, uint256[] calldata chainIds)
//         internal
//         view
//         returns (bytes memory)
//     {
//         bytes memory publicData;

//         // old and new state root pairs
//         for (uint256 i = 0; i < chainIds.length; i++) {
//             publicData = bytes.concat(publicData, _stateRoots[chainIds[i]], newStateRoots[i]);
//         }

//         // blobhash
//         publicData = bytes.concat(publicData, _getBlobHash());

//         // last block hash
//         publicData = bytes.concat(publicData, _lastBlockHash);

//         // get shared bridge's rolling hashes for each chain
//         for (uint256 i = 0; i < chainIds.length; i++) {
//             IScopedCallable.RollingHashes memory rollingHashes = _sharedBridge.getRollingHashes(chainIds[i]);
//             publicData = bytes.concat(
//                 publicData,
//                 bytes32(rollingHashes.requestsIn),
//                 bytes32(rollingHashes.requestsOut),
//                 bytes32(rollingHashes.responsesIn),
//                 bytes32(rollingHashes.responsesOut)
//             );
//         }
//         return publicData;
//     }
// }
