// SPDX-License-Identifier: MIT
//  __  __   ______   ______   ______
// /_/\/_/\ /_____/\ /_____/\ /_____/\
// \:\ \:\ \\::::_\/_\:::_ \ \\:::_:\ \
//  \:\ \:\ \\:\/___/\\:\ \ \ \\:\_\:\ \
//   \:\ \:\ \\_::._\:\\:\ \ \ \\::__:\ \
//    \:\_\:\ \ /____\:\\:\/.:| |\:\_\:\ \
//     \_____\/ \_____\/ \____/_/ \_____\/

pragma solidity 0.8.28;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Burnable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title USD8Booster
/// @notice ERC-1155 booster NFT for USD8. Holding one NFT grants a 1% boost
///         to the holder's USD8 cover score when making a claim. No supply cap.
///         NFTs can either be issued directly by the admin or claimed with a
///         valid EIP-712 signature from the admin or authorized signer.
///         details: https://usd8.fi/boosters.html
/// @custom:security-contact rick@usd8.fi

contract USD8Booster is ERC1155, ERC1155Burnable, ERC1155Supply, EIP712 {
    // Token ID conventions:
    //   1 = 1% cover score booster
    // Add future token IDs here as new booster tiers are introduced.

    /// @notice Immutable admin set at deployment. Cannot be transferred or renounced.
    address public immutable admin;

    /// @notice Authorized signer for EIP-712 claim signatures. Rotatable by admin.
    address public signer;

    /// @notice EIP-712 typehash for a claim authorization.
    bytes32 public constant CLAIM_TYPEHASH =
        keccak256("Claim(address receiver,uint256 nonce,uint256 tokenId,uint256 amount)");

    /// @notice Tracks consumed nonces globally to prevent replay.
    mapping(uint256 nonce => bool used) public nonceUsed;

    event Claimed(address indexed receiver, uint256 nonce, uint256 indexed tokenId, uint256 indexed amount);
    event NonceInvalidated(uint256 indexed nonce);
    event SignerRotated(address indexed previousSigner, address indexed newSigner);

    error Unauthorized();
    error InvalidSignature();
    error NonceAlreadyUsed();
    error ZeroAmount();
    error ZeroAddress();
    error LengthMismatch();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    constructor(string memory uri_) ERC1155(uri_) EIP712("USD8Booster", "1") {
        admin = msg.sender;
    }

    /// @notice Admin-only: rotate the authorized signer.
    function setSigner(address newSigner) external onlyAdmin {
        if (newSigner == address(0)) revert ZeroAddress();
        emit SignerRotated(signer, newSigner);
        signer = newSigner;
    }

    /// @notice Admin-only mint. Admin may mint any amount of any token id to any address.
    function mint(address to, uint256 tokenId, uint256 amount) external onlyAdmin {
        _mint(to, tokenId, amount, "");
    }

    /// @notice Admin-only batch mint to multiple recipients.
    function mintBatch(address[] calldata recipients, uint256[] calldata tokenIds, uint256[] calldata amounts)
        external
        onlyAdmin
    {
        if (recipients.length != amounts.length || recipients.length != tokenIds.length) {
            revert LengthMismatch();
        }
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], tokenIds[i], amounts[i], "");
        }
    }

    /// @notice Update the metadata URI.
    function setURI(string calldata newuri) external onlyAdmin {
        _setURI(newuri);
    }

    /// @notice Invalidate a nonce so that any signature referencing it can no longer be claimed.
    function invalidateNonce(uint256 nonce) external onlyAdmin {
        if (nonceUsed[nonce]) revert NonceAlreadyUsed();
        nonceUsed[nonce] = true;
        emit NonceInvalidated(nonce);
    }

    /// @notice Claim `amount` booster NFTs of `tokenId` to `receiver`, authorized by the signer.
    /// @param receiver  The address that receives the minted NFTs.
    /// @param nonce     Globally unique nonce for this claim.
    /// @param tokenId   Token id to mint.
    /// @param amount    Number of NFTs to mint.
    /// @param signature EIP-712 signature over (receiver, nonce, tokenId, amount) produced by the signer.
    function claim(address receiver, uint256 nonce, uint256 tokenId, uint256 amount, bytes calldata signature)
        external
    {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (nonceUsed[nonce]) revert NonceAlreadyUsed();

        bytes32 structHash = keccak256(abi.encode(CLAIM_TYPEHASH, receiver, nonce, tokenId, amount));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = ECDSA.recover(digest, signature);
        if (recovered != signer && recovered != admin) revert InvalidSignature();

        nonceUsed[nonce] = true;
        _mint(receiver, tokenId, amount, "");

        emit Claimed(receiver, nonce, tokenId, amount);
    }

    /// @notice Exposes the EIP-712 domain separator for off-chain signers.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }
}
