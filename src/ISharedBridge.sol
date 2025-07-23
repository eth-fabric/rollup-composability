// SPDX-License-Identifier: MIT
pragma solidity =0.8.29;

import {ICrossChainCaller} from "./ICrossChainCaller.sol";

interface ISharedBridge {
    function deposit(uint256 chainId, address l2Recipient) external payable;

    function xCall(uint256 chainId, address from, ICrossChainCaller.CrossCall memory txn)
        external
        returns (bytes memory);

    error UnsupportedChain();
}
