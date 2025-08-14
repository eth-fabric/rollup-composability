// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IScopedCallable} from "../src/IScopedCallable.sol";
import {ScopedCallable} from "../src/ScopedCallable.sol";
import {SharedBridge} from "../src/SharedBridge.sol";
import {BridgeL2} from "../src/BridgeL2.sol";
import {IBridgeL2} from "../src/IBridgeL2.sol";
import {ISharedBridge} from "../src/ISharedBridge.sol";

contract SharedBridgeMock is SharedBridge {
    constructor(address sequencer, uint256 chainId) SharedBridge(sequencer, chainId) {}

    function editLockedEth(uint256 chainId, uint256 amount) external {
        deposits[chainId][ETH_TOKEN][ETH_TOKEN] += amount;
    }
}

contract TargetContract {
    uint256 state;

    function updateState() external returns (uint256) {
        state++;
        return state;
    }

    function getState() external view returns (uint256) {
        return state;
    }
}

contract ComposabilityTester is Test {
    SharedBridgeMock public mainnet;
    BridgeL2 public rollup;
    uint256 public mainnetId = 1;
    uint256 public rollupId = 2;
    address public sequencer = makeAddr("sequencer");

    /// @notice Struct to hold cross-chain call parameters
    struct CrossCallParams {
        address target;
        bytes data;
        uint256 value;
        uint256 gasLimit;
        uint256 sourceChainId;
        uint256 targetChainId;
        address from;
        uint256 nonce;
    }

    function setUp() public {
        mainnet = new SharedBridgeMock(sequencer, mainnetId);
        rollup = new BridgeL2(address(mainnet), rollupId, sequencer, makeAddr("owner"));

        vm.prank(sequencer);
        mainnet.editSupportedChain(rollupId, true);

        vm.prank(sequencer);
        rollup.editSupportedChain(mainnetId, true);

        vm.prank(sequencer);
        mainnet.setL2BridgeAddress(rollupId, address(rollup));

        // Give the rollup some ETH to mint
        vm.deal(address(rollup), 100 ether);
    }

    /// @notice Helper function to create a CrossCall and calculate its transaction hash
    /// @param params The CrossCallParams struct containing all call parameters
    /// @return txn The CrossCall struct
    /// @return txHash The calculated transaction hash
    function createCrossCallAndHash(CrossCallParams memory params)
        internal
        view
        returns (IScopedCallable.ScopedRequest memory txn, bytes32 txHash)
    {
        txn = IScopedCallable.ScopedRequest({
            to: params.target,
            gasLimit: params.gasLimit,
            value: params.value,
            data: params.data
        });

        txHash = mainnet.getTransactionHash(params.sourceChainId, params.targetChainId, params.from, params.nonce, txn);
    }

    function test_l1ToL2_deposit() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        uint256 nonce = 0;
        vm.deal(alice, 100 ether);
        uint256[] memory chainIds = new uint256[](1);
        bytes[] memory results = new bytes[](1);
        bytes32[] memory resultHashes = new bytes32[](1);

        // Prepopulate the L1 result inbox with mintETH() result
        // No xCalls initiated from L2 to L1, so no need to prepopulate the L2 result inbox
        chainIds[0] = rollupId;
        results[0] = ""; // mintETH() return empty bytes
        resultHashes[0] = keccak256(""); // deposit() and mintETH() return empty bytes
        mainnet.fillResponsesIn(chainIds, resultHashes, results);

        // Deposit via mainnet shared bridge
        vm.prank(alice);
        mainnet.deposit{value: 1 ether}(rollupId, bob);

        // Reconstruct the outbound L1->L2 transaction using helper
        (IScopedCallable.ScopedRequest memory txn,) = createCrossCallAndHash(
            CrossCallParams({
                target: mainnet.l2BridgeAddresses(rollupId),
                data: abi.encodeCall(IBridgeL2.mintETH, (bob)),
                value: 1 ether,
                gasLimit: 21000 * 5,
                sourceChainId: mainnetId,
                targetChainId: rollupId,
                from: alice,
                nonce: nonce
            })
        );

        // Execute the L2 privileged transaction handler
        // This will call the mintETH() function on the rollup
        vm.startPrank(address(rollup));
        rollup.handleScopedCall(mainnetId, mainnet.l2BridgeAddresses(rollupId), nonce, txn);
        vm.stopPrank();

        // Verify balances are correct
        assertEq(alice.balance, 99 ether);
        assertEq(bob.balance, 1 ether);

        // Verify mailbox states
        assert(mainnet.rollingHashesEqual(rollupId, rollup.getRollingHashes(mainnetId)));
    }

    function test_l2ToL1_withdrawal() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        uint256 nonce = 0;
        vm.deal(alice, 100 ether);
        uint256[] memory chainIds = new uint256[](1);
        bytes[] memory results = new bytes[](1);
        bytes32[] memory resultHashes = new bytes32[](1);

        // Prepopulate the L2 result inbox with withdraw() result
        // No xCalls initiated from L1 to L2, so no need to prepopulate the L1 result inbox
        chainIds[0] = mainnetId;
        results[0] = ""; // withdraw() return empty bytes
        resultHashes[0] = keccak256(""); // withdraw() return empty bytes
        rollup.fillResponsesIn(chainIds, resultHashes, results);

        // Pretend the rollup has 1 ETH locked already
        mainnet.editLockedEth(rollupId, 1 ether);
        vm.deal(address(mainnet), 1 ether);

        // Withdraw via rollup
        vm.prank(alice);
        rollup.withdraw{value: 1 ether}(mainnetId, bob);

        // Reconstruct the outbound L2->L1 transaction using helper
        (IScopedCallable.ScopedRequest memory txn,) = createCrossCallAndHash(
            CrossCallParams({
                target: address(mainnet),
                data: abi.encodeCall(ISharedBridge.handleWithdrawal, (rollupId, bob, 1 ether)),
                value: 0,
                gasLimit: 21000 * 5,
                sourceChainId: rollupId,
                targetChainId: mainnetId,
                from: address(rollup),
                nonce: nonce
            })
        );

        // Execute the L2 privileged transaction handler
        // This will call the handleWithdrawal() function on the mainnet
        vm.startPrank(sequencer);
        mainnet.handleScopedCall(rollupId, address(rollup), nonce, txn);
        vm.stopPrank();

        // Verify balances are correct
        assertEq(alice.balance, 99 ether);
        assertEq(bob.balance, 1 ether);

        // Verify mailbox states
        assert(mainnet.rollingHashesEqual(rollupId, rollup.getRollingHashes(mainnetId)));
    }

    function test_l1ToL2_call() public {
        TargetContract target = new TargetContract(); // assume lives on L2
        address alice = makeAddr("alice");
        uint256 nonce = 0;
        vm.deal(alice, 100 ether);
        uint256[] memory chainIds = new uint256[](1);
        bytes[] memory results = new bytes[](1);
        bytes32[] memory txHashes = new bytes32[](1);

        // Construct the outbound L1->L2 transaction
        (IScopedCallable.ScopedRequest memory txn, bytes32 txHash) = createCrossCallAndHash(
            CrossCallParams({
                target: address(target),
                data: abi.encodeCall(TargetContract.updateState, ()),
                value: 0,
                gasLimit: 21000 * 5,
                sourceChainId: mainnetId,
                targetChainId: rollupId,
                from: alice,
                nonce: nonce
            })
        );

        // Prepopulate the L1 result inbox with updateState() result for the xCall to read from
        chainIds[0] = rollupId; // Result is from the rollup
        results[0] = abi.encode(1); // updateState() would return 1
        txHashes[0] = txHash; // transaction hash that will be used by xCall
        mainnet.fillResponsesIn(chainIds, txHashes, results);

        // Execute the xCall from L1
        vm.startPrank(sequencer);
        bytes memory result = mainnet.scopedCall(rollupId, alice, txn);
        vm.stopPrank();

        // Execute the xCallHandler from L2
        vm.startPrank(address(rollup));
        rollup.handleScopedCall(mainnetId, alice, nonce, txn);
        vm.stopPrank();

        // Verify the result
        assertEq(result, abi.encode(target.getState()), "result != target.getState()");

        // Verify mailbox states
        assert(mainnet.rollingHashesEqual(rollupId, rollup.getRollingHashes(mainnetId)));
    }

    function test_l2ToL1_call() public {
        TargetContract target = new TargetContract(); // assume lives on L1
        address alice = makeAddr("alice");
        uint256 nonce = 0;
        vm.deal(alice, 100 ether);
        uint256[] memory chainIds = new uint256[](1);
        bytes[] memory results = new bytes[](1);
        bytes32[] memory txHashes = new bytes32[](1);

        // Construct the outbound L2->L1 transaction
        (IScopedCallable.ScopedRequest memory txn, bytes32 txHash) = createCrossCallAndHash(
            CrossCallParams({
                target: address(target),
                data: abi.encodeCall(TargetContract.updateState, ()),
                value: 0,
                gasLimit: 21000 * 5,
                sourceChainId: rollupId,
                targetChainId: mainnetId,
                from: alice,
                nonce: nonce
            })
        );

        // Prepopulate the L2 result inbox with updateState() result
        chainIds[0] = mainnetId; // Result is from mainnet
        results[0] = abi.encode(1); // updateState() would return 1
        txHashes[0] = txHash; // transaction hash that will be used by xCall
        rollup.fillResponsesIn(chainIds, txHashes, results);

        // Execute the xCall from L2
        vm.startPrank(sequencer);
        bytes memory result = rollup.scopedCall(mainnetId, alice, txn);
        vm.stopPrank();

        // Execute the xCallHandler from L1
        vm.startPrank(address(sequencer));
        mainnet.handleScopedCall(rollupId, alice, nonce, txn);
        vm.stopPrank();

        // Verify the result
        assertEq(result, abi.encode(target.getState()), "result != target.getState()");

        // Verify mailbox states
        assert(mainnet.rollingHashesEqual(rollupId, rollup.getRollingHashes(mainnetId)));
    }
}
