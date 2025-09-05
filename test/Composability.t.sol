// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IScopedCallable} from "../src/IScopedCallable.sol";
import {SharedBridge} from "../src/SharedBridge.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";

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

// Assume this is a user contract on mainnet
contract UserContract {
    address payable public mainnet;
    address payable public rollup;
    address public target;

    constructor(address payable _mainnet, address payable _rollup, address _target) {
        mainnet = _mainnet;
        rollup = _rollup;
        target = _target;
    }

    function crossChainAction() public {
        bytes[] memory attributes = new bytes[](0);

        // Target contract as an interoperable address
        bytes memory recipient = InteroperableAddress.formatEvmV1(block.chainid, target);

        // Payload to be sent cross chain
        bytes memory data = abi.encodeWithSelector(TargetContract(target).updateState.selector);

        // Make the call on mainnet
        bytes32 sendId = SharedBridge(mainnet).sendMessage(recipient, data, attributes);

        // Read the response on mainnet
        bytes memory response = SharedBridge(mainnet).readResponsesInboxValue(sendId);
        (uint256 number) = abi.decode(response, (uint256));

        // Do something with the response
        require(number == 1, "new state should be 1");
    }
}

contract ComposabilityTester is Test {
    SharedBridge public mainnet;
    SharedBridge public rollup;
    TargetContract public target;
    UserContract public user;

    bytes public mainnetAddress;
    bytes public rollupAddress;
    address owner = makeAddr("owner");
    address gateway = makeAddr("gateway");

    function setUp() public {
        address[] memory gateways = new address[](1);
        gateways[0] = gateway;
        bytes4[] memory attributes = new bytes4[](1);
        attributes[0] = 0x00000000;

        target = new TargetContract();
        mainnet = new SharedBridge(owner, gateways, attributes);
        rollup = new SharedBridge(owner, gateways, attributes);
        user = new UserContract(payable(mainnet), payable(rollup), address(target));

        // For local testing, we use the same chainid for both
        mainnetAddress = mainnet.bridgeAddress();
        rollupAddress = rollup.bridgeAddress();

        // Register the remote bridges
        vm.prank(owner);
        mainnet.registerRemoteBridge(rollupAddress);
        vm.prank(owner);
        rollup.registerRemoteBridge(mainnetAddress);

        // Set up some initial balance for the bridges
        vm.deal(address(mainnet), 10000 ether);
        vm.deal(address(rollup), 10000 ether);
    }

    function test_crossChainAction() public {
        // Nonce at start of test
        uint256 nonce = 0;

        bytes memory sender = InteroperableAddress.formatEvmV1(block.chainid, address(user));
        bytes memory recipient = InteroperableAddress.formatEvmV1(block.chainid, address(target));

        // get the payload to be sent
        bytes memory data = abi.encodeWithSelector(TargetContract(target).updateState.selector);

        // wrap payload as sendMessage does
        bytes memory wrappedPayload = abi.encode(++nonce, sender, recipient, 0, data);

        bytes[] memory bridges = new bytes[](1);
        bridges[0] = rollupAddress;

        bytes32[] memory requestHashes = new bytes32[](1);
        requestHashes[0] = keccak256(wrappedPayload);

        bytes[] memory simulatedResponses = new bytes[](1);
        simulatedResponses[0] = abi.encode(1); // The "simulated" response

        bytes32 sendId = mainnet._calcStorageKey(rollupAddress, keccak256(wrappedPayload));

        // Execute the message on the rollup
        vm.startPrank(gateway);
        rollup.receiveMessage(sendId, sender, wrappedPayload);
        vm.stopPrank();

        // Check the state was updated on rollup
        assertEq(target.getState(), 1, "state should be 1");

        mainnet.fillResponsesIn(bridges, requestHashes, simulatedResponses);

        // Initiate the sendMessage call via a user contract
        user.crossChainAction();
    }
}
