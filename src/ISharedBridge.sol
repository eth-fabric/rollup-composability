// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IScopedCallable} from "./IScopedCallable.sol";

interface ISharedBridge {
    function deposit(uint256 chainId, address l2Recipient) external payable;

    function scopedCall(uint256 chainId, address from, IScopedCallable.ScopedRequest memory request)
        external
        returns (bytes memory);

    function handleScopedCall(
        uint256 sourceChainId,
        address from,
        uint256 nonce,
        IScopedCallable.ScopedRequest memory request
    ) external;

    function handleWithdrawal(uint256 sourceChainId, address to, uint256 amount) external;

    event WithdrawalProcessed(address indexed to, uint256 amount);

    error UnsupportedToken();
    error InvalidSender();
    error OnlySequencer();

    event SequencerUpdated(address indexed oldSequencer, address indexed newSequencer);
}
