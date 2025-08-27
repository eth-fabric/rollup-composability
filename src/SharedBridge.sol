// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ScopedCallable} from "./ScopedCallable.sol";
import {IScopedCallable} from "./IScopedCallable.sol";
import {IERC7786GatewaySource, IERC7786Receiver} from "./IERC7786.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract SharedBridge is ScopedCallable, IERC7786GatewaySource, IERC7786Receiver, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using InteroperableAddress for bytes;

    struct Request {
        address to;
        uint256 gasLimit;
        bytes data;
    }

    /**
     *
     *                                        E V E N T S   &   E R R O R S                                         *
     *
     */
    event Received(bytes32 indexed receiveId, address gateway);
    event ExecutionSuccess(bytes32 indexed receiveId);
    event GatewayAdded(address indexed gateway);
    event GatewayRemoved(address indexed gateway);
    event RemoteRegistered(bytes remote);

    error RemoteAlreadyRegistered(bytes remote);

    error ERC7786GatewayAlreadyRegistered(address gateway);
    error ERC7786GatewayNotRegistered(address gateway);
    error ERC7786RemoteNotRegistered(bytes2 chainType, bytes chainReference);
    error InvalidReceiveId(bytes32 receiveId);
    error InvalidRecipient(bytes32 receiveId);
    error InvalidSender(bytes32 receiveId);
    error ExecutionFailed(bytes32 receiveId);
    error OnlySelfCanCall();

    /**
     *
     *                                        S T A T E   V A R I A B L E S                                         *
     *
     */
    /// @dev address of the matching bridge for a given CAIP2 chain
    mapping(bytes2 chainType => mapping(bytes chainReference => bytes addr)) private _remotes;

    /// @dev List of authorized IERC7786 gateways (M is the length of this set)
    EnumerableSet.AddressSet private _gateways;

    // / @dev Supported attributes for the bridge
    EnumerableSet.Bytes32Set private _supportedAttributes;

    // @dev Nonce for message deduplication (internal)
    uint256 private _nonce;

    /**
     *
     *                                              M O D I F I E R S                                               *
     *
     */
    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelfCanCall();
        _;
    }

    /**
     *
     *                                              F U N C T I O N S                                               *
     *
     */
    constructor(address owner_, address[] memory gateways_, bytes4[] memory attributes_) Ownable(owner_) {
        for (uint256 i = 0; i < gateways_.length; i++) {
            _addGateway(gateways_[i]);
        }
        for (uint256 i = 0; i < attributes_.length; i++) {
            _supportedAttributes.add(bytes32(attributes_[i]));
        }
    }

    // ============================================ IERC7786GatewaySource ============================================

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) public view virtual returns (bool) {
        return _supportedAttributes.contains(bytes32(selector));
    }

    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        external
        payable
        virtual
        returns (bytes32 sendId)
    {
        // Check if the attributes are supported
        for (uint256 i = 0; i < attributes.length; i++) {
            if (!supportsAttribute(bytes4(attributes[i]))) {
                revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[i]));
            }
        }

        // Interoperable address of the remote bridge, revert if not registered
        bytes memory bridge = getRemoteBridge(recipient);

        // Interoperable address of the bridge
        bytes memory sender = bridgeId();

        // Wrap the payload with the nonce, sender, and recipient
        bytes memory wrappedPayload = abi.encode(++_nonce, sender, recipient, msg.value, payload);

        // Generate unique request hash using nonce
        bytes32 requestHash = keccak256(wrappedPayload);

        // Update rolling hash with requestHash
        _updateRollingHash(bridge, requestHash, RollingHashType.REQUESTS_OUT);

        // sendId is the storage location of the response for the calling function to synchronously read
        // This allows compatibility with the ERC7786 spec since we can't explicitly return bytes
        sendId = _calcStorageKey(bridge, requestHash);

        emit MessageSent(sendId, sender, recipient, payload, msg.value, attributes);
    }

    // ============================================== IERC7786Receiver ===============================================

    /// @inheritdoc IERC7786Receiver
    function receiveMessage(bytes32 receiveId, bytes calldata sender, bytes calldata payload)
        external
        payable
        virtual
        returns (bytes4)
    {
        // Only gateways can call this function
        if (!_gateways.contains(msg.sender)) revert ERC7786GatewayNotRegistered(msg.sender);

        // Recompute the request hash from the *wrapped* payload
        bytes32 requestHash = keccak256(payload);

        // Parse payload
        (, bytes memory originalSender, bytes memory recipient, uint256 value, bytes memory unwrappedPayload) =
            abi.decode(payload, (uint256, bytes, bytes, uint256, bytes));

        // The receiveId should match the sendId
        if (receiveId != _calcStorageKey(recipient, requestHash)) {
            revert InvalidReceiveId(receiveId);
        }

        // The recipient should be the bridgeId
        if (keccak256(recipient) != keccak256(bridgeId())) revert InvalidRecipient(receiveId);

        // The sender should match the original sender
        if (keccak256(sender) != keccak256(originalSender)) revert InvalidSender(receiveId);

        // Update rolling hash with requestHash
        _updateRollingHash(sender, requestHash, RollingHashType.REQUESTS_IN);

        // Decode the request from the payload
        Request memory request = abi.decode(unwrappedPayload, (Request));

        // Execute local call
        (bool success, bytes memory response) = request.to.call{gas: request.gasLimit, value: value}(request.data);

        if (!success) revert ExecutionFailed(receiveId);

        // Update rolling response outbox hash
        _updateRollingHash(sender, keccak256(response), RollingHashType.RESPONSES_OUT);

        // Emit for sequencer to populate source-chain's responsesInboxValues
        emit ExecutionSuccess(receiveId);

        // // Return the selector of the executeMessage function as required by the ERC7786 spec
        return IERC7786Receiver.receiveMessage.selector;
    }

    // =================================================== Getters ===================================================
    function bridgeId() public view returns (bytes memory) {
        return InteroperableAddress.formatEvmV1(block.chainid, address(this));
    }

    function getGateways() public view returns (address[] memory) {
        return _gateways.values();
    }

    function getSupportedAttributes() public view returns (bytes32[] memory) {
        return _supportedAttributes.values();
    }

    function getRemoteBridge(bytes memory chain) public view returns (bytes memory) {
        (bytes2 chainType, bytes memory chainReference,) = chain.parseV1();
        return getRemoteBridge(chainType, chainReference);
    }

    function getRemoteBridge(bytes2 chainType, bytes memory chainReference) public view returns (bytes memory) {
        bytes memory addr = _remotes[chainType][chainReference];
        require(bytes(addr).length != 0, ERC7786RemoteNotRegistered(chainType, chainReference));
        return InteroperableAddress.formatV1(chainType, chainReference, addr);
    }

    // =================================================== Setters ===================================================
    function addGateway(address gateway) public virtual onlyOwner {
        _addGateway(gateway);
    }

    function removeGateway(address gateway) public virtual onlyOwner {
        _removeGateway(gateway);
    }

    function addSupportedAttribute(bytes4 selector) external onlyOwner {
        _supportedAttributes.add(bytes32(selector));
    }

    function removeSupportedAttribute(bytes4 selector) external onlyOwner {
        _supportedAttributes.remove(bytes32(selector));
    }

    function registerRemoteBridge(bytes calldata bridge) public virtual onlyOwner {
        _registerRemoteBridge(bridge);
    }

    // ================================================== Internal ===================================================
    function _addGateway(address gateway) internal virtual {
        require(_gateways.add(gateway), ERC7786GatewayAlreadyRegistered(gateway));
        emit GatewayAdded(gateway);
    }

    function _removeGateway(address gateway) internal virtual {
        require(_gateways.remove(gateway), ERC7786GatewayNotRegistered(gateway));
        emit GatewayRemoved(gateway);
    }

    function _registerRemoteBridge(bytes calldata bridge) internal virtual {
        (bytes2 chainType, bytes calldata chainReference, bytes calldata addr) = bridge.parseV1Calldata();
        _remotes[chainType][chainReference] = addr;
        emit RemoteRegistered(bridge);
    }

    receive() external payable {
        revert("SharedBridge: must use deposit()");
    }
}
