// SPDX-License-Identifier: MIT
pragma solidity =0.8.29;

import {CrossChainCaller} from "./CrossChainCaller.sol";
import {ICrossChainCaller} from "./ICrossChainCaller.sol";
import {ISharedBridge} from "./ISharedBridge.sol";
import {IBridgeL2} from "./IBridgeL2.sol";

contract BridgeL2 is CrossChainCaller, IBridgeL2 {
    address public constant L1_MESSENGER = 0x000000000000000000000000000000000000FFFE;
    address public constant BURN_ADDRESS = 0x0000000000000000000000000000000000000000;
    /// @notice Token address used to represent ETH
    address public constant ETH_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public L1_BRIDGE;

    // Some calls come as a privileged transaction, whose sender is the bridge itself.
    modifier onlySelf() {
        require(msg.sender == address(this), "BridgeL2: caller is not the bridge");
        _;
    }

    constructor(address _l1Bridge, uint256 chainId_) CrossChainCaller(chainId_) {
        L1_BRIDGE = _l1Bridge;
    }

    function withdraw(uint256 targetChainId, address _receiver) external payable {
        require(msg.value > 0, "Withdrawal amount must be positive");

        (bool success,) = BURN_ADDRESS.call{value: msg.value}("");
        require(success, "Failed to burn Ether");

        emit WithdrawalInitiated(msg.sender, _receiver, msg.value);

        ICrossChainCaller.CrossCall memory crossCall = ICrossChainCaller.CrossCall({
            to: L1_BRIDGE,
            gasLimit: 21000 * 5,
            value: 0,
            data: abi.encodeCall(ISharedBridge.handleWithdrawal, (_chainId, _receiver, msg.value))
        });

        // Initiate cross-chain withdrawal at the target chain
        _xCall(targetChainId, msg.sender, crossCall);
    }

    function xCallHandler(uint256 sourceChainId, address from, uint256 nonce, ICrossChainCaller.CrossCall memory txn)
        external
        onlySelf
    {
        // todo check if supported source chain
        _xCallHandler(sourceChainId, from, nonce, txn);
    }

    function mintETH(address to) external payable onlySelf {
        (bool success,) = to.call{value: msg.value}("");
        require(success, "BridgeL2: failed to mint ETH");
        emit DepositProcessed(to, msg.value);
    }
}
