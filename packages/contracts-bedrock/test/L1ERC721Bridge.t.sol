// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { ERC721Bridge_Initializer } from "./CommonTest.t.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Target contract dependencies
import { L2ERC721Bridge } from "../src/L2/L2ERC721Bridge.sol";
import { Predeploys } from "../src/libraries/Predeploys.sol";

// Target contract
import { L1ERC721Bridge } from "../src/L1/L1ERC721Bridge.sol";

/// @dev Test ERC721 contract.
contract TestERC721 is ERC721 {
    constructor() ERC721("Test", "TST") {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}

contract L1ERC721Bridge_Test is ERC721Bridge_Initializer {
    TestERC721 internal localToken;
    TestERC721 internal remoteToken;
    uint256 internal constant tokenId = 1;

    event ERC721BridgeInitiated(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 tokenId,
        bytes extraData
    );

    event ERC721BridgeFinalized(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 tokenId,
        bytes extraData
    );

    /// @dev Sets up the testing environment.
    function setUp() public override {
        super.setUp();

        localToken = new TestERC721();
        remoteToken = new TestERC721();

        // Mint alice a token.
        localToken.mint(alice, tokenId);

        // Approve the bridge to transfer the token.
        vm.prank(alice);
        localToken.approve(address(L1Bridge), tokenId);
    }

    /// @dev Tests that the constructor sets the correct values.
    function test_constructor_succeeds() public {
        assertEq(address(L1Bridge.MESSENGER()), address(L1Messenger));
        assertEq(address(L1Bridge.OTHER_BRIDGE()), Predeploys.L2_ERC721_BRIDGE);
        assertEq(address(L1Bridge.messenger()), address(L1Messenger));
        assertEq(address(L1Bridge.otherBridge()), Predeploys.L2_ERC721_BRIDGE);
    }

    /// @dev Tests that the ERC721 can be bridged successfully.
    function test_bridgeERC721_succeeds() public {
        // Expect a call to the messenger.
        vm.expectCall(
            address(L1Messenger),
            abi.encodeCall(
                L1Messenger.sendMessage,
                (
                    address(L2Bridge),
                    abi.encodeCall(
                        L2ERC721Bridge.finalizeBridgeERC721,
                        (
                            address(remoteToken),
                            address(localToken),
                            alice,
                            alice,
                            tokenId,
                            hex"5678"
                        )
                    ),
                    1234
                )
            )
        );

        // Expect an event to be emitted.
        vm.expectEmit(true, true, true, true);
        emit ERC721BridgeInitiated(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            hex"5678"
        );

        // Bridge the token.
        vm.prank(alice);
        L1Bridge.bridgeERC721(address(localToken), address(remoteToken), tokenId, 1234, hex"5678");

        // Token is locked in the bridge.
        assertEq(L1Bridge.deposits(address(localToken), address(remoteToken), tokenId), true);
        assertEq(localToken.ownerOf(tokenId), address(L1Bridge));
    }

    /// @dev Tests that the ERC721 bridge reverts for non externally owned accounts.
    function test_bridgeERC721_fromContract_reverts() external {
        // Bridge the token.
        vm.etch(alice, hex"01");
        vm.prank(alice);
        vm.expectRevert("ERC721Bridge: account is not externally owned");
        L1Bridge.bridgeERC721(address(localToken), address(remoteToken), tokenId, 1234, hex"5678");

        // Token is not locked in the bridge.
        assertEq(L1Bridge.deposits(address(localToken), address(remoteToken), tokenId), false);
        assertEq(localToken.ownerOf(tokenId), alice);
    }

    /// @dev Tests that the ERC721 bridge reverts for a zero address local token.
    function test_bridgeERC721_localTokenZeroAddress_reverts() external {
        // Bridge the token.
        vm.prank(alice);
        vm.expectRevert();
        L1Bridge.bridgeERC721(address(0), address(remoteToken), tokenId, 1234, hex"5678");

        // Token is not locked in the bridge.
        assertEq(L1Bridge.deposits(address(localToken), address(remoteToken), tokenId), false);
        assertEq(localToken.ownerOf(tokenId), alice);
    }

    /// @dev Tests that the ERC721 bridge reverts for a zero address remote token.
    function test_bridgeERC721_remoteTokenZeroAddress_reverts() external {
        // Bridge the token.
        vm.prank(alice);
        vm.expectRevert("L1ERC721Bridge: remote token cannot be address(0)");
        L1Bridge.bridgeERC721(address(localToken), address(0), tokenId, 1234, hex"5678");

        // Token is not locked in the bridge.
        assertEq(L1Bridge.deposits(address(localToken), address(remoteToken), tokenId), false);
        assertEq(localToken.ownerOf(tokenId), alice);
    }

    /// @dev Tests that the ERC721 bridge reverts for an incorrect owner.
    function test_bridgeERC721_wrongOwner_reverts() external {
        // Bridge the token.
        vm.prank(bob);
        vm.expectRevert("ERC721: transfer from incorrect owner");
        L1Bridge.bridgeERC721(address(localToken), address(remoteToken), tokenId, 1234, hex"5678");

        // Token is not locked in the bridge.
        assertEq(L1Bridge.deposits(address(localToken), address(remoteToken), tokenId), false);
        assertEq(localToken.ownerOf(tokenId), alice);
    }

    /// @dev Tests that the ERC721 bridge successfully sends a token
    ///      to a different address than the owner.
    function test_bridgeERC721To_succeeds() external {
        // Expect a call to the messenger.
        vm.expectCall(
            address(L1Messenger),
            abi.encodeCall(
                L1Messenger.sendMessage,
                (
                    address(Predeploys.L2_ERC721_BRIDGE),
                    abi.encodeCall(
                        L2ERC721Bridge.finalizeBridgeERC721,
                        (address(remoteToken), address(localToken), alice, bob, tokenId, hex"5678")
                    ),
                    1234
                )
            )
        );

        // Expect an event to be emitted.
        vm.expectEmit(true, true, true, true);
        emit ERC721BridgeInitiated(
            address(localToken),
            address(remoteToken),
            alice,
            bob,
            tokenId,
            hex"5678"
        );

        // Bridge the token.
        vm.prank(alice);
        L1Bridge.bridgeERC721To(
            address(localToken),
            address(remoteToken),
            bob,
            tokenId,
            1234,
            hex"5678"
        );

        // Token is locked in the bridge.
        assertEq(L1Bridge.deposits(address(localToken), address(remoteToken), tokenId), true);
        assertEq(localToken.ownerOf(tokenId), address(L1Bridge));
    }

    /// @dev Tests that the ERC721 bridge reverts for non externally owned accounts
    ///      when sending to a different address than the owner.
    function test_bridgeERC721To_localTokenZeroAddress_reverts() external {
        // Bridge the token.
        vm.prank(alice);
        vm.expectRevert();
        L1Bridge.bridgeERC721To(address(0), address(remoteToken), bob, tokenId, 1234, hex"5678");

        // Token is not locked in the bridge.
        assertEq(L1Bridge.deposits(address(localToken), address(remoteToken), tokenId), false);
        assertEq(localToken.ownerOf(tokenId), alice);
    }

    /// @dev Tests that the ERC721 bridge reverts for a zero address remote token
    ///      when sending to a different address than the owner.
    function test_bridgeERC721To_remoteTokenZeroAddress_reverts() external {
        // Bridge the token.
        vm.prank(alice);
        vm.expectRevert("L1ERC721Bridge: remote token cannot be address(0)");
        L1Bridge.bridgeERC721To(address(localToken), address(0), bob, tokenId, 1234, hex"5678");

        // Token is not locked in the bridge.
        assertEq(L1Bridge.deposits(address(localToken), address(remoteToken), tokenId), false);
        assertEq(localToken.ownerOf(tokenId), alice);
    }

    /// @dev Tests that the ERC721 bridge reverts for an incorrect owner
    ////     when sending to a different address than the owner.
    function test_bridgeERC721To_wrongOwner_reverts() external {
        // Bridge the token.
        vm.prank(bob);
        vm.expectRevert("ERC721: transfer from incorrect owner");
        L1Bridge.bridgeERC721To(
            address(localToken),
            address(remoteToken),
            bob,
            tokenId,
            1234,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(L1Bridge.deposits(address(localToken), address(remoteToken), tokenId), false);
        assertEq(localToken.ownerOf(tokenId), alice);
    }

    /// @dev Tests that the ERC721 bridge successfully finalizes a withdrawal.
    function test_finalizeBridgeERC721_succeeds() external {
        // Bridge the token.
        vm.prank(alice);
        L1Bridge.bridgeERC721(address(localToken), address(remoteToken), tokenId, 1234, hex"5678");

        // Expect an event to be emitted.
        vm.expectEmit(true, true, true, true);
        emit ERC721BridgeFinalized(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            hex"5678"
        );

        // Finalize a withdrawal.
        vm.mockCall(
            address(L1Messenger),
            abi.encodeWithSelector(L1Messenger.xDomainMessageSender.selector),
            abi.encode(Predeploys.L2_ERC721_BRIDGE)
        );
        vm.prank(address(L1Messenger));
        L1Bridge.finalizeBridgeERC721(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(L1Bridge.deposits(address(localToken), address(remoteToken), tokenId), false);
        assertEq(localToken.ownerOf(tokenId), alice);
    }

    /// @dev Tests that the ERC721 bridge finalize reverts when not called
    ///      by the remote bridge.
    function test_finalizeBridgeERC721_notViaLocalMessenger_reverts() external {
        // Finalize a withdrawal.
        vm.prank(alice);
        vm.expectRevert("ERC721Bridge: function can only be called from the other bridge");
        L1Bridge.finalizeBridgeERC721(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            hex"5678"
        );
    }

    /// @dev Tests that the ERC721 bridge finalize reverts when not called
    ///      from the remote messenger.
    function test_finalizeBridgeERC721_notFromRemoteMessenger_reverts() external {
        // Finalize a withdrawal.
        vm.mockCall(
            address(L1Messenger),
            abi.encodeWithSelector(L1Messenger.xDomainMessageSender.selector),
            abi.encode(alice)
        );
        vm.prank(address(L1Messenger));
        vm.expectRevert("ERC721Bridge: function can only be called from the other bridge");
        L1Bridge.finalizeBridgeERC721(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            hex"5678"
        );
    }

    /// @dev Tests that the ERC721 bridge finalize reverts when the local token
    ///      is set as the bridge itself.
    function test_finalizeBridgeERC721_selfToken_reverts() external {
        // Finalize a withdrawal.
        vm.mockCall(
            address(L1Messenger),
            abi.encodeWithSelector(L1Messenger.xDomainMessageSender.selector),
            abi.encode(Predeploys.L2_ERC721_BRIDGE)
        );
        vm.prank(address(L1Messenger));
        vm.expectRevert("L1ERC721Bridge: local token cannot be self");
        L1Bridge.finalizeBridgeERC721(
            address(L1Bridge),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            hex"5678"
        );
    }

    /// @dev Tests that the ERC721 bridge finalize reverts when the remote token
    ///      is not escrowed in the L1 bridge.
    function test_finalizeBridgeERC721_notEscrowed_reverts() external {
        // Finalize a withdrawal.
        vm.mockCall(
            address(L1Messenger),
            abi.encodeWithSelector(L1Messenger.xDomainMessageSender.selector),
            abi.encode(Predeploys.L2_ERC721_BRIDGE)
        );
        vm.prank(address(L1Messenger));
        vm.expectRevert("L1ERC721Bridge: Token ID is not escrowed in the L1 Bridge");
        L1Bridge.finalizeBridgeERC721(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            hex"5678"
        );
    }
}
