// SPDX-License-Identifier: MIT
pragma solidity =0.8.29;

import {CrossChainCaller} from "./CrossChainCaller.sol";
import {ICrossChainCaller} from "./ICrossChainCaller.sol";
import {ISharedBridge} from "./ISharedBridge.sol";
import {IBridgeL2} from "./IBridgeL2.sol";

contract SharedBridge is CrossChainCaller, ISharedBridge {
    address public ON_CHAIN_PROPOSER;

    /// @notice How much of each L1 token was deposited to each L2 token.
    /// @dev Stored as chain -> L1 -> L2 -> amount
    /// @dev Prevents L2 tokens from faking their L1 address and stealing tokens
    /// @dev The token can take the value {ETH_TOKEN} to represent ETH
    mapping(uint256 chainId => mapping(address l1User => mapping(address token => uint256 amount))) public deposits;

    /// @notice Address of the bridge on the L2
    /// @dev It's used to validate withdrawals
    address public constant L2_BRIDGE_ADDRESS = address(0xffff);

    /// @notice Token address used to represent ETH
    address public constant ETH_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    mapping(uint256 chainId => bool supported) public supportedChains;

    modifier onlyOnChainProposer() {
        require(msg.sender == ON_CHAIN_PROPOSER, "CommonBridge: caller is not the OnChainProposer");
        _;
    }

    constructor(address onChainProposer, uint256 chainId) CrossChainCaller(chainId) {
        require(onChainProposer != address(0), "BasicBridge: onChainProposer is the zero address");
        ON_CHAIN_PROPOSER = onChainProposer;
    }

    function editSupportedChain(uint256 chainId, bool supported) external onlyOnChainProposer {
        supportedChains[chainId] = supported;
    }

    /// @inheritdoc ISharedBridge
    function deposit(uint256 chainId, address l2Recipient) public payable {
        if (!supportedChains[chainId]) revert UnsupportedChain();
        _deposit(chainId, l2Recipient);
    }

    function xCall(uint256 chainId, address from, CrossCall memory txn)
        external
        onlyOnChainProposer
        returns (bytes memory)
    {
        if (!supportedChains[chainId]) revert UnsupportedChain();
        return _xCall(chainId, from, txn);
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
        _xCall(chainId, msg.sender, crossCall);
    }

    receive() external payable {
        revert("SharedBridge: must use deposit()");
    }
}
