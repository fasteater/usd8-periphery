// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {USD8Booster} from "../src/USD8Booster.sol";

contract USD8BoosterTest is Test {
    USD8Booster internal booster;

    uint256 internal adminPk = 0xA11CE;
    address internal admin;
    uint256 internal signerPk = 0x516E;
    address internal signer;
    address internal alice = address(0xA);
    address internal bob = address(0xB);

    uint256 internal constant TOKEN_ID = 1;

    bytes32 internal constant CLAIM_TYPEHASH =
        keccak256("Claim(address receiver,uint256 nonce,uint256 tokenId,uint256 amount)");

    function setUp() public {
        admin = vm.addr(adminPk);
        signer = vm.addr(signerPk);
        vm.prank(admin);
        booster = new USD8Booster("ipfs://booster/{id}.json");
    }

    function _sign(uint256 pk, address receiver, uint256 nonce, uint256 tokenId, uint256 amount)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(CLAIM_TYPEHASH, receiver, nonce, tokenId, amount));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", booster.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    // ---- admin / signer setup ----

    function test_AdminIsDeployer() public view {
        assertEq(booster.admin(), admin);
    }

    function test_SignerStartsAsZero() public view {
        assertEq(booster.signer(), address(0));
    }

    function test_AdminCanSetSigner() public {
        vm.prank(admin);
        booster.setSigner(signer);
        assertEq(booster.signer(), signer);
    }

    function test_NonAdminCannotSetSigner() public {
        vm.prank(alice);
        vm.expectRevert(USD8Booster.Unauthorized.selector);
        booster.setSigner(signer);
    }

    function test_SetSignerRejectsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(USD8Booster.ZeroAddress.selector);
        booster.setSigner(address(0));
    }

    // ---- admin mint ----

    function test_AdminCanMint() public {
        vm.prank(admin);
        booster.mint(alice, TOKEN_ID, 5);
        assertEq(booster.balanceOf(alice, TOKEN_ID), 5);
    }

    function test_AdminCanMintDifferentTokenIds() public {
        vm.startPrank(admin);
        booster.mint(alice, 1, 5);
        booster.mint(alice, 2, 3);
        vm.stopPrank();
        assertEq(booster.balanceOf(alice, 1), 5);
        assertEq(booster.balanceOf(alice, 2), 3);
    }

    function test_AdminMintBatch() public {
        address[] memory to = new address[](2);
        to[0] = alice;
        to[1] = bob;
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 3;
        amounts[1] = 7;
        vm.prank(admin);
        booster.mintBatch(to, tokenIds, amounts);
        assertEq(booster.balanceOf(alice, 1), 3);
        assertEq(booster.balanceOf(bob, 1), 7);
    }

    function test_NonAdminCannotMint() public {
        vm.prank(alice);
        vm.expectRevert(USD8Booster.Unauthorized.selector);
        booster.mint(alice, TOKEN_ID, 1);
    }

    function test_MintBatchRevertsOnAmountLengthMismatch() public {
        address[] memory to = new address[](2);
        to[0] = alice;
        to[1] = bob;
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 3;
        vm.prank(admin);
        vm.expectRevert(USD8Booster.LengthMismatch.selector);
        booster.mintBatch(to, tokenIds, amounts);
    }

    function test_MintBatchRevertsOnTokenIdLengthMismatch() public {
        address[] memory to = new address[](2);
        to[0] = alice;
        to[1] = bob;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 2;
        vm.prank(admin);
        vm.expectRevert(USD8Booster.LengthMismatch.selector);
        booster.mintBatch(to, tokenIds, amounts);
    }

    // ---- claim: admin signs (default fallback when signer unset) ----

    function test_UserCanClaimWithAdminSignature() public {
        bytes memory sig = _sign(adminPk, bob, 1, TOKEN_ID, 2);
        vm.prank(bob);
        booster.claim(bob, 1, TOKEN_ID, 2, sig);
        assertEq(booster.balanceOf(bob, TOKEN_ID), 2);
        assertTrue(booster.nonceUsed(1));
    }

    // ---- claim: signer signs ----

    function test_UserCanClaimWithSignerSignature() public {
        vm.prank(admin);
        booster.setSigner(signer);

        bytes memory sig = _sign(signerPk, bob, 1, TOKEN_ID, 2);
        vm.prank(bob);
        booster.claim(bob, 1, TOKEN_ID, 2, sig);
        assertEq(booster.balanceOf(bob, TOKEN_ID), 2);
    }

    function test_AdminSigStillWorksAfterSignerSet() public {
        vm.prank(admin);
        booster.setSigner(signer);

        bytes memory sig = _sign(adminPk, bob, 1, TOKEN_ID, 2);
        vm.prank(bob);
        booster.claim(bob, 1, TOKEN_ID, 2, sig);
        assertEq(booster.balanceOf(bob, TOKEN_ID), 2);
    }

    function test_AnyoneCanRelayClaim() public {
        // Signature authorizes a mint to `bob`; anyone can submit it,
        // tokens still end up with bob.
        bytes memory sig = _sign(adminPk, bob, 1, TOKEN_ID, 3);
        vm.prank(alice);
        booster.claim(bob, 1, TOKEN_ID, 3, sig);
        assertEq(booster.balanceOf(bob, TOKEN_ID), 3);
        assertEq(booster.balanceOf(alice, TOKEN_ID), 0);
    }

    function test_ClaimRevertsOnBadSignature() public {
        uint256 wrongPk = 0xBEEF;
        bytes memory sig = _sign(wrongPk, bob, 1, TOKEN_ID, 1);
        vm.prank(bob);
        vm.expectRevert(USD8Booster.InvalidSignature.selector);
        booster.claim(bob, 1, TOKEN_ID, 1, sig);
    }

    function test_ClaimRevertsIfAmountTampered() public {
        bytes memory sig = _sign(adminPk, bob, 1, TOKEN_ID, 1);
        vm.prank(bob);
        vm.expectRevert(USD8Booster.InvalidSignature.selector);
        booster.claim(bob, 1, TOKEN_ID, 99, sig);
    }

    function test_ClaimRevertsIfTokenIdTampered() public {
        bytes memory sig = _sign(adminPk, bob, 1, 1, 1);
        vm.prank(bob);
        vm.expectRevert(USD8Booster.InvalidSignature.selector);
        booster.claim(bob, 1, 2, 1, sig);
    }

    function test_ClaimRevertsIfReceiverTampered() public {
        bytes memory sig = _sign(adminPk, bob, 1, TOKEN_ID, 1);
        vm.prank(alice);
        vm.expectRevert(USD8Booster.InvalidSignature.selector);
        booster.claim(alice, 1, TOKEN_ID, 1, sig);
    }

    function test_ClaimRevertsOnNonceReuse() public {
        bytes memory sig = _sign(adminPk, bob, 1, TOKEN_ID, 1);
        vm.prank(bob);
        booster.claim(bob, 1, TOKEN_ID, 1, sig);

        vm.prank(bob);
        vm.expectRevert(USD8Booster.NonceAlreadyUsed.selector);
        booster.claim(bob, 1, TOKEN_ID, 1, sig);
    }

    function test_ClaimRevertsOnZeroAmount() public {
        bytes memory sig = _sign(adminPk, bob, 1, TOKEN_ID, 0);
        vm.prank(bob);
        vm.expectRevert(USD8Booster.ZeroAmount.selector);
        booster.claim(bob, 1, TOKEN_ID, 0, sig);
    }

    function test_ClaimRevertsOnZeroReceiver() public {
        bytes memory sig = _sign(adminPk, address(0), 1, TOKEN_ID, 1);
        vm.prank(bob);
        vm.expectRevert(USD8Booster.ZeroAddress.selector);
        booster.claim(address(0), 1, TOKEN_ID, 1, sig);
    }

    // ---- signer rotation ----

    function test_SignerRotationInvalidatesOldSignerSigs() public {
        uint256 newSignerPk = 0xFACE;
        address newSigner = vm.addr(newSignerPk);

        vm.prank(admin);
        booster.setSigner(signer);

        vm.prank(admin);
        booster.setSigner(newSigner);

        bytes memory staleSig = _sign(signerPk, bob, 1, TOKEN_ID, 1);
        vm.prank(bob);
        vm.expectRevert(USD8Booster.InvalidSignature.selector);
        booster.claim(bob, 1, TOKEN_ID, 1, staleSig);

        bytes memory freshSig = _sign(newSignerPk, bob, 2, TOKEN_ID, 5);
        vm.prank(bob);
        booster.claim(bob, 2, TOKEN_ID, 5, freshSig);
        assertEq(booster.balanceOf(bob, TOKEN_ID), 5);
    }

    // ---- burn ----

    function test_HolderCanBurn() public {
        vm.prank(admin);
        booster.mint(alice, TOKEN_ID, 5);

        vm.prank(alice);
        booster.burn(alice, TOKEN_ID, 2);
        assertEq(booster.balanceOf(alice, TOKEN_ID), 3);
    }

    function test_NonHolderCannotBurn() public {
        vm.prank(admin);
        booster.mint(alice, TOKEN_ID, 5);

        vm.prank(bob);
        vm.expectRevert();
        booster.burn(alice, TOKEN_ID, 1);
    }

    function test_ApprovedOperatorCanBurn() public {
        vm.prank(admin);
        booster.mint(alice, TOKEN_ID, 5);

        vm.prank(alice);
        booster.setApprovalForAll(bob, true);

        vm.prank(bob);
        booster.burn(alice, TOKEN_ID, 4);
        assertEq(booster.balanceOf(alice, TOKEN_ID), 1);
    }

    // ---- total supply ----

    function test_TotalSupplyTracksMintsAndBurns() public {
        assertEq(booster.totalSupply(TOKEN_ID), 0);

        vm.prank(admin);
        booster.mint(alice, TOKEN_ID, 5);
        assertEq(booster.totalSupply(TOKEN_ID), 5);

        vm.prank(admin);
        booster.mint(bob, TOKEN_ID, 3);
        assertEq(booster.totalSupply(TOKEN_ID), 8);

        vm.prank(alice);
        booster.burn(alice, TOKEN_ID, 2);
        assertEq(booster.totalSupply(TOKEN_ID), 6);
    }

    function test_ExistsReflectsSupply() public {
        assertFalse(booster.exists(TOKEN_ID));
        vm.prank(admin);
        booster.mint(alice, TOKEN_ID, 1);
        assertTrue(booster.exists(TOKEN_ID));
    }

    // ---- invalidate nonce ----

    function test_InvalidateNonce() public {
        vm.prank(admin);
        booster.invalidateNonce(42);
        assertTrue(booster.nonceUsed(42));

        bytes memory sig = _sign(adminPk, bob, 42, TOKEN_ID, 1);
        vm.prank(bob);
        vm.expectRevert(USD8Booster.NonceAlreadyUsed.selector);
        booster.claim(bob, 42, TOKEN_ID, 1, sig);
    }

    function test_InvalidateNonceRevertsIfAlreadyUsed() public {
        vm.prank(admin);
        booster.invalidateNonce(1);

        vm.prank(admin);
        vm.expectRevert(USD8Booster.NonceAlreadyUsed.selector);
        booster.invalidateNonce(1);
    }

    function test_NonAdminCannotInvalidateNonce() public {
        vm.prank(alice);
        vm.expectRevert(USD8Booster.Unauthorized.selector);
        booster.invalidateNonce(1);
    }

    // ---- URI ----

    function test_AdminCanSetURI() public {
        string memory newURI = "ipfs://new/{id}.json";
        vm.prank(admin);
        booster.setURI(newURI);
        assertEq(booster.uri(TOKEN_ID), newURI);
    }

    function test_NonAdminCannotSetURI() public {
        vm.prank(alice);
        vm.expectRevert(USD8Booster.Unauthorized.selector);
        booster.setURI("ipfs://new/{id}.json");
    }
}
