// SPDX-License-Identifier: MIT
pragma solidity =0.8.29;

interface IBridgeL2 {
    /// @notice An ETH deposit was successfully processed
    /// @dev Event emitted when an ETH deposit is processed.
    /// @param receiver the address that received the ETH
    /// @param amount the amount of ether being deposited
    event DepositProcessed(address indexed receiver, uint256 amount);
    /// @notice A withdrawal to L1 has initiated.
    /// @dev Event emitted when a withdrawal is initiated.
    /// @param senderOnL2 the sender of the transaction on L2.
    /// @param receiverOnL1 the address on L1 that will receive the funds back.
    /// @param amount the amount of ether being withdrawn.
    event WithdrawalInitiated(address indexed senderOnL2, address indexed receiverOnL1, uint256 indexed amount);

    /// @notice Initiates the withdrawal of funds to the L1.
    /// @dev This is the first step in the two step process of a user withdrawal.
    /// @dev It burns funds on L2 and sends a message to the L1 so users
    /// @dev can claim those funds on L1.
    /// @param targetChainId the chain ID of the target chain
    /// @param _receiver the address that can claim the funds on L1.
    function withdraw(uint256 targetChainId, address _receiver) external payable;

    /// @notice Transfers ETH to the given address.
    /// @dev This is called by a privileged transaction from the L1 bridge
    /// @dev The transaction itself is what mints the ETH, this is just a helper
    /// @dev If the transfer fails, a withdrawal is initiated.
    /// @param to the address to transfer the funds to
    function mintETH(address to) external payable;
}
