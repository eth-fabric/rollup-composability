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
        bytes memory rollupId = SharedBridge(rollup).bridgeId();
        bytes memory payload = getPayload();
        bytes[] memory attributes = new bytes[](0);

        // Make the call on mainnet
        bytes32 sendId = SharedBridge(mainnet).sendMessage(rollupId, payload, attributes);

        // Read the response on mainnet
        bytes memory response = SharedBridge(mainnet).readResponsesInboxValue(sendId);
        (uint256 number) = abi.decode(response, (uint256));

        // Do something with the response
        require(number == 1, "new state should be 1");
    }

    function getPayload() public returns (bytes memory) {
        bytes memory data = abi.encodeWithSelector(TargetContract(target).updateState.selector);
        bytes memory payload = abi.encode(SharedBridge.Request({to: address(target), gasLimit: 1000000, data: data}));
        return payload;
    }
}

contract ComposabilityTester is Test {
    SharedBridge public mainnet;
    SharedBridge public rollup;
    TargetContract public target;
    UserContract public user;

    bytes public mainnetId;
    bytes public rollupId;
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
        mainnetId = mainnet.bridgeId();
        rollupId = rollup.bridgeId();

        // Register the remote bridges
        vm.prank(owner);
        mainnet.registerRemoteBridge(rollupId);
        vm.prank(owner);
        rollup.registerRemoteBridge(mainnetId);

        // Set up some initial balance for the bridges
        vm.deal(address(mainnet), 10000 ether);
        vm.deal(address(rollup), 10000 ether);
    }

    function test_crossChainAction() public {
        // get the payload to be sent
        bytes memory payload = user.getPayload();
        uint256 nonce = 0;

        bytes memory wrappedPayload = abi.encode(++nonce, mainnetId, rollupId, 0, payload);

        bytes[] memory bridges = new bytes[](1);
        bridges[0] = rollupId;

        bytes32[] memory requestHashes = new bytes32[](1);
        requestHashes[0] = keccak256(wrappedPayload);

        bytes[] memory simulatedResponses = new bytes[](1);
        simulatedResponses[0] = abi.encode(1); // The "simulated" response

        // Execute the message on the rollup
        vm.startPrank(gateway);
        rollup.receiveMessage(mainnet._calcStorageKey(rollupId, keccak256(wrappedPayload)), mainnetId, wrappedPayload);
        vm.stopPrank();

        // Check the state was updated on rollup
        assertEq(target.getState(), 1, "state should be 1");

        mainnet.fillResponsesIn(bridges, requestHashes, simulatedResponses);

        // Initiate the sendMessage call via a user contract
        user.crossChainAction();
    }
}
