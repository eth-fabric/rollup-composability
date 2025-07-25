// SPDX-License-Identifier: MIT
pragma solidity =0.8.29;

import {CrossChainCaller} from "./CrossChainCaller.sol";
import {ICrossChainCaller} from "./ICrossChainCaller.sol";
import {ISharedBridge} from "./ISharedBridge.sol";
import {IBridgeL2} from "./IBridgeL2.sol";

contract SharedBridge is CrossChainCaller, ISharedBridge {
    address public SEQUENCER;

    /// @notice How much of each L1 token was deposited to each L2 token.
    /// @dev Stored as chain -> L1 -> L2 -> amount
    /// @dev Prevents L2 tokens from faking their L1 address and stealing tokens
    /// @dev The token can take the value {ETH_TOKEN} to represent ETH
    mapping(uint256 chainId => mapping(address l1User => mapping(address token => uint256 amount))) public deposits;

    /// @notice Address of the bridge on the L2
    /// @dev It's used to validate withdrawals
    // todo need per supported chain
    address public constant L2_BRIDGE_ADDRESS = address(0xffff);

    /// @notice Token address used to represent ETH
    address public constant ETH_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    modifier onlySequencer() {
        require(msg.sender == SEQUENCER, "SharedBridge: caller is not the Sequencer");
        _;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "SharedBridge: caller is not the bridge");
        _;
    }

    constructor(address sequencer, uint256 chainId) CrossChainCaller(chainId) {
        require(sequencer != address(0), "SharedBridge: sequencer is the zero address");
        SEQUENCER = sequencer;
    }

    /// @inheritdoc ISharedBridge
    function deposit(uint256 chainId, address l2Recipient) external payable {
        if (!_chainSupported(chainId)) revert UnsupportedChain();
        _deposit(chainId, l2Recipient);
    }

    function xCall(uint256 chainId, address from, CrossCall memory txn) external onlySequencer returns (bytes memory) {
        if (!_chainSupported(chainId)) revert UnsupportedChain();

        // Only deposit() can use the L2 bridge address
        if (from == L2_BRIDGE_ADDRESS) revert InvalidSender();
        return _xCall(chainId, from, txn);
    }

    function xCallHandler(uint256 sourceChainId, address from, uint256 nonce, CrossCall memory txn)
        external
        onlySequencer
    {
        if (!_chainSupported(sourceChainId)) revert UnsupportedChain();
        _xCallHandler(sourceChainId, from, nonce, txn);
    }

    // for now, only ETH is supported
    function handleWithdrawal(uint256 sourceChainId, address to, uint256 amount) external onlySelf {
        if (!_chainSupported(sourceChainId)) revert UnsupportedChain();

        deposits[sourceChainId][ETH_TOKEN][ETH_TOKEN] -= amount;

        (bool success,) = payable(to).call{value: amount}("");
        require(success, "SharedBridge: failed to handle withdrawal");

        emit WithdrawalProcessed(to, amount);
    }

    function editSupportedChain(uint256 chainId, bool supported) external onlySequencer {
        _editSupportedChain(chainId, supported);
    }

    /// Burns at least {amount} gas
    function _burnGas(uint256 amount) private view {
        uint256 startingGas = gasleft();
        while (startingGas - gasleft() < amount) {}
    }

    function _deposit(uint256 chainId, address l2Recipient) private {
        deposits[chainId][ETH_TOKEN][ETH_TOKEN] += msg.value;
        bytes memory callData = abi.encodeCall(IBridgeL2.mintETH, (l2Recipient));
        CrossCall memory crossCall =
            CrossCall({to: L2_BRIDGE_ADDRESS, gasLimit: 21000 * 5, value: msg.value, data: callData});

        _burnGas(crossCall.gasLimit);

        // The from address must be the L2 bridge address to mint ETH on L2
        _xCall(chainId, L2_BRIDGE_ADDRESS, crossCall);
    }

    receive() external payable {
        revert("SharedBridge: must use deposit()");
    }
}
