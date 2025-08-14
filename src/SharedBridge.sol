// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ScopedCallable} from "./ScopedCallable.sol";
import {IScopedCallable} from "./IScopedCallable.sol";
import {ISharedBridge} from "./ISharedBridge.sol";
import {IBridgeL2} from "./IBridgeL2.sol";

contract SharedBridge is ScopedCallable, ISharedBridge {
    address public sequencer;

    /// @notice How much of each L1 token was deposited to each L2 token.
    /// @dev Stored as chain -> L1 -> L2 -> amount
    /// @dev Prevents L2 tokens from faking their L1 address and stealing tokens
    /// @dev The token can take the value {ETH_TOKEN} to represent ETH
    mapping(uint256 chainId => mapping(address l1User => mapping(address token => uint256 amount))) public deposits;

    /// @notice Address of the bridge on the specified L2
    mapping(uint256 chainId => address l2BridgeAddress) public l2BridgeAddresses;

    /// @notice Token address used to represent ETH
    address public constant ETH_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    modifier onlySequencer() {
        if (msg.sender != sequencer) revert OnlySequencer();
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert InvalidSender();
        _;
    }

    constructor(address sequencer_, uint256 chainId) ScopedCallable(chainId) {
        _setSequencer(sequencer_);
    }

    /// @inheritdoc ISharedBridge
    function deposit(uint256 chainId, address l2Recipient) external payable {
        if (!_chainSupported(chainId)) revert UnsupportedChain();
        _deposit(chainId, l2Recipient);
    }

    function scopedCall(uint256 chainId, address from, ScopedRequest memory request)
        external
        onlySequencer
        returns (bytes memory)
    {
        if (!_chainSupported(chainId)) revert UnsupportedChain();

        // Only deposit() can use the L2 bridge address
        if (from == l2BridgeAddresses[chainId]) revert InvalidSender();
        return _scopedCall(chainId, from, request);
    }

    function handleScopedCall(uint256 sourceChainId, address from, uint256 nonce, ScopedRequest memory request)
        external
        onlySequencer
    {
        if (!_chainSupported(sourceChainId)) revert UnsupportedChain();
        _handleScopedCall(sourceChainId, from, nonce, request);
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

    function setL2BridgeAddress(uint256 chainId, address l2BridgeAddress) external onlySequencer {
        l2BridgeAddresses[chainId] = l2BridgeAddress;
    }

    /// Burns at least {amount} gas
    function _burnGas(uint256 amount) private view {
        uint256 startingGas = gasleft();
        while (startingGas - gasleft() < amount) {}
    }

    function _setSequencer(address newSequencer) internal {
        address oldSequencer = sequencer;
        sequencer = newSequencer;
        emit SequencerUpdated(oldSequencer, newSequencer);
    }

    function _deposit(uint256 chainId, address l2Recipient) private {
        deposits[chainId][ETH_TOKEN][ETH_TOKEN] += msg.value;
        bytes memory callData = abi.encodeCall(IBridgeL2.mintETH, (l2Recipient));
        ScopedRequest memory scopedRequest =
            ScopedRequest({to: l2BridgeAddresses[chainId], gasLimit: 21000 * 5, value: msg.value, data: callData});

        _burnGas(scopedRequest.gasLimit);

        // The from address must be the L2 bridge address to mint ETH on L2
        _scopedCall(chainId, l2BridgeAddresses[chainId], scopedRequest);
    }

    receive() external payable {
        revert("SharedBridge: must use deposit()");
    }
}
