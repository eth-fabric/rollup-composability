// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IERC7786GatewaySource {
    event MessagePosted(bytes32 indexed outboxId, string sender, string receiver, bytes payload, uint256 value, bytes[] attributes);
 
    error UnsupportedAttribute(bytes4 selector);
 
    function supportsAttribute(bytes4 selector) external view returns (bool);
 
    function sendMessage(
        string calldata destinationChain, // CAIP-2 chain identifier
        string calldata receiver, // CAIP-10 account address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 outboxId);
}

interface IERC7786Receiver {
    function executeMessage(
        string calldata sourceChain, // CAIP-2 chain identifier
        string calldata sender, // CAIP-10 account address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes4);
}