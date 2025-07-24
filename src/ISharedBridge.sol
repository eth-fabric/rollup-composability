// SPDX-License-Identifier: MIT
pragma solidity =0.8.29;

import {ICrossChainCaller} from "./ICrossChainCaller.sol";

interface ISharedBridge {
    function deposit(uint256 chainId, address l2Recipient) external payable;

    function xCall(uint256 chainId, address from, ICrossChainCaller.CrossCall memory txn)
        external
        returns (bytes memory);

    function xCallHandler(uint256 sourceChainId, address from, uint256 nonce, ICrossChainCaller.CrossCall memory txn)
        external;

    function handleWithdrawal(uint256 sourceChainId, address to, uint256 amount) external;

    event WithdrawalProcessed(address indexed to, uint256 amount);

    error UnsupportedChain();
    error UnsupportedToken();
}
