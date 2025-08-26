// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.13;

// import {Test, console} from "forge-std/Test.sol";
// import {ScopedCallable} from "../src/ScopedCallable.sol";
// import {IScopedCallable} from "../src/IScopedCallable.sol";
// import {IBridgeL2} from "../src/IBridgeL2.sol";
// import {ISharedBridge} from "../src/ISharedBridge.sol";

// contract Foo {
//     function bar() public pure returns (uint256) {
//         return 42;
//     }
// }

// contract CrossChainCallerTester is Test {
//     ScopedCallable public chainA;
//     ScopedCallable public chainB;
//     Foo public foo;
//     string public chainAId = "eip155:123456";
//     string public chainBId = "eip155:654321";

//     function setUp() public {
//         chainA = new ScopedCallable(chainAId);
//         chainB = new ScopedCallable(chainBId);
//         foo = new Foo();

//         // whitelist Foo.bar() as an attribute
//         // chainA.editSupportedAttribute(Foo.bar.selector, true);
//         // chainB.editSupportedAttribute(Foo.bar.selector, true);
//         chainA.editSupportedAttribute(0x00000000, true);
//         chainB.editSupportedAttribute(0x00000000, true);
//     }

//     // function test_scopedCall() public {
//     //     address from = makeAddr("alice");
//     //     uint256 nonce = chainA.globalScopedCallNonce();

//     //     IScopedCallable.ScopedRequest memory txn = IScopedCallable.ScopedRequest({
//     //         to: address(foo),
//     //         value: 0,
//     //         gasLimit: 1000000,
//     //         data: abi.encodeWithSelector(Foo.bar.selector)
//     //     });

//     //     bytes32 txHash = chainA.getTransactionHash(chainAId, chainBId, from, nonce, txn);

//     //     // Assume sequencer has simulated ahead of time
//     //     uint256[] memory chainIds = new uint256[](1);
//     //     bytes32[] memory txHashes = new bytes32[](1);
//     //     bytes[] memory results = new bytes[](1);
//     //     chainIds[0] = chainBId;
//     //     txHashes[0] = txHash;
//     //     results[0] = abi.encode(foo.bar());

//     //     // Pre-populate chainA's inbox with results
//     //     chainA.fillResponsesIn(chainIds, txHashes, results);

//     //     // Call the xCallHandler on chainB (would be called in their rollup execution environment)
//     //     chainB.handleScopedCall(chainAId, from, nonce, txn);

//     //     // Call the xCall on chainA
//     //     bytes memory response = chainA.scopedCall(chainBId, from, txn);

//     //     // Check the result value returned correctly
//     //     assertEq(response, abi.encode(foo.bar()));

//     //     // Check the result value written correctly and hashed correctly
//     //     assertEq(
//     //         chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.RESPONSES_IN),
//     //         keccak256(
//     //             abi.encodePacked(
//     //                 bytes32(0), // rolling hash is building on empty bytes32
//     //                 keccak256(chainA.readResponsesInboxValue(chainBId, txHash))
//     //             )
//     //         )
//     //     );

//     //     // MAILBOX EQUIVALENCE CHECKS

//     //     // ChainB handled scopedCall requests from ChainA in order
//     //     assertEq(
//     //         chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.REQUESTS_OUT),
//     //         chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.REQUESTS_IN),
//     //         "A's requestsOutbox should be equal to B's requestsInbox"
//     //     );

//     //     // ChainA received responses from ChainB in order
//     //     assertEq(
//     //         chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.RESPONSES_OUT),
//     //         chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.RESPONSES_IN),
//     //         "A's responsesOutbox should be equal to B's responsesInbox"
//     //     );

//     //     // ChainB received responses from ChainA in order
//     //     assertEq(
//     //         chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.RESPONSES_IN),
//     //         chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.RESPONSES_OUT),
//     //         "A's responsesInbox should be equal to B's responsesOutbox"
//     //     );

//     //     // ChainA handled scopedCall requests from ChainB in order
//     //     assertEq(
//     //         chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.REQUESTS_IN),
//     //         chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.REQUESTS_OUT),
//     //         "A's requestsInbox should be equal to B's requestsOutbox"
//     //     );
//     // }

//     function test_sendMessage() public {
//         string memory from = "eip155:1:0x1234567890abcdef1234567890abcdef12345678";

//         IScopedCallable.ScopedRequest memory request = IScopedCallable.ScopedRequest({
//             to: address(foo),
//             value: 0,
//             gasLimit: 1000000,
//             data: abi.encodeWithSelector(Foo.bar.selector)
//         });
//         bytes memory payload = abi.encode(request);

//         // add attribute
//         bytes[] memory attributes = new bytes[](1);
//         // attributes[0] = abi.encode(Foo.bar.selector);

//         bytes32 requestHash = chainA.getRequestHash(chainBId, from, payload, attributes);

//         // Assume sequencer has simulated ahead of time to determine the response
//         string[] memory chainIds = new string[](1);
//         bytes32[] memory requestHashes = new bytes32[](1);
//         bytes[] memory expectedResponses = new bytes[](1);
//         chainIds[0] = chainBId;
//         requestHashes[0] = requestHash;
//         expectedResponses[0] = abi.encode(foo.bar());

//         // Pre-populate chainA's inbox with results
//         chainA.fillResponsesIn(chainIds, requestHashes, expectedResponses);

//         // Call the executeMessage handler on chainB (would be called in their rollup execution environment)
//         chainB.executeMessage(chainAId, from, payload, attributes);

//         // Call the sendMessage on chainA
//         bytes32 requestLocation = chainA.sendMessage(chainBId, from, payload, attributes);

//         // Read the response from the inbox
//         bytes memory response = chainA.readResponsesInboxValue(requestLocation);

//         // Check the response value returned correctly
//         assertEq(response, expectedResponses[0], "response should be equal to expected response");

//         // Check the response value written correctly and hashed correctly
//         assertEq(
//             chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.RESPONSES_IN),
//             keccak256(
//                 abi.encodePacked(
//                     bytes32(0), // rolling hash is building on empty bytes32
//                     keccak256(response)
//                 )
//             )
//         );

//         // MAILBOX EQUIVALENCE CHECKS

//         // ChainB handled scopedCall requests from ChainA in order
//         assertEq(
//             chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.REQUESTS_OUT),
//             chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.REQUESTS_IN),
//             "A's requestsOutbox should be equal to B's requestsInbox"
//         );

//         // ChainA received responses from ChainB in order
//         assertEq(
//             chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.RESPONSES_OUT),
//             chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.RESPONSES_IN),
//             "A's responsesOutbox should be equal to B's responsesInbox"
//         );

//         // ChainB received responses from ChainA in order
//         assertEq(
//             chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.RESPONSES_IN),
//             chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.RESPONSES_OUT),
//             "A's responsesInbox should be equal to B's responsesOutbox"
//         );

//         // ChainA handled scopedCall requests from ChainB in order
//         assertEq(
//             chainA.readRollingHash(chainBId, IScopedCallable.RollingHashType.REQUESTS_IN),
//             chainB.readRollingHash(chainAId, IScopedCallable.RollingHashType.REQUESTS_OUT),
//             "A's requestsInbox should be equal to B's requestsOutbox"
//         );
//     }
// }
