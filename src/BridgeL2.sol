// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ScopedCallable} from "./ScopedCallable.sol";
import {IScopedCallable} from "./IScopedCallable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ISharedBridge} from "./ISharedBridge.sol";
import {IBridgeL2} from "./IBridgeL2.sol";

contract BridgeL2 is ScopedCallable, IBridgeL2 {
    address public constant L1_MESSENGER = 0x000000000000000000000000000000000000FFFE;
    address public constant BURN_ADDRESS = 0x0000000000000000000000000000000000000000;
    /// @notice Token address used to represent ETH
    address public constant ETH_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public immutable l1Bridge;
    address public sequencer;
    address public owner;

    // Some calls come as a privileged transaction, whose sender is the bridge itself.
    modifier onlySelf() {
        if (msg.sender != address(this)) revert InvalidSender();
        _;
    }

    modifier onlySequencer() {
        if (msg.sender != sequencer) revert OnlySequencer();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _l1Bridge, uint256 chainId_, address sequencer_, address owner_) ScopedCallable(chainId_) {
        l1Bridge = _l1Bridge;
        _setSequencer(sequencer_);
        owner = owner_;
    }

    function scopedCall(uint256 targetChainId, address from, ScopedRequest memory request)
        external
        payable
        override
        onlySequencer
        returns (bytes memory response)
    {
        if (!_chainSupported(targetChainId)) revert UnsupportedChain();
        response = _scopedCall(targetChainId, from, request);
    }

    function handleScopedCall(
        uint256 sourceChainId,
        address from,
        uint256 nonce,
        IScopedCallable.ScopedRequest memory request
    ) external override onlySelf {
        if (!_chainSupported(sourceChainId)) revert UnsupportedChain();
        _handleScopedCall(sourceChainId, from, nonce, request);
    }

    function mintETH(address to) external payable onlySelf {
        (bool success,) = to.call{value: msg.value}("");
        require(success, "BridgeL2: failed to mint ETH");
        emit DepositProcessed(to, msg.value);
    }

    function withdraw(uint256 targetChainId, address _receiver) external payable {
        require(msg.value > 0, "Withdrawal amount must be positive");

        (bool success,) = BURN_ADDRESS.call{value: msg.value}("");
        require(success, "Failed to burn Ether");

        emit WithdrawalInitiated(msg.sender, _receiver, msg.value);

        IScopedCallable.ScopedRequest memory scopedRequest = IScopedCallable.ScopedRequest({
            to: l1Bridge,
            gasLimit: 21000 * 5,
            value: 0,
            data: abi.encodeCall(ISharedBridge.handleWithdrawal, (_chainId, _receiver, msg.value))
        });

        // Initiate cross-chain withdrawal at the target chain
        _scopedCall(targetChainId, address(this), scopedRequest);
    }

    function setSequencer(address newSequencer) external onlyOwner {
        _setSequencer(newSequencer);
    }

    function _setSequencer(address newSequencer) internal {
        address oldSequencer = sequencer;
        sequencer = newSequencer;
        emit SequencerUpdated(oldSequencer, newSequencer);
    }

    function editSupportedChain(uint256 chainId, bool supported) external onlySequencer {
        _editSupportedChain(chainId, supported);
    }
}
