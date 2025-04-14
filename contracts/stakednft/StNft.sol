// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ERC721EnumerableUpgradeable, ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC721MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import {IStakedNft} from "../interfaces/IStakedNft.sol";
import {INftVault} from "../interfaces/INftVault.sol";
import {IBNFTRegistry} from "../interfaces/IBNFTRegistry.sol";

abstract contract StNft is IStakedNft, OwnableUpgradeable, ReentrancyGuardUpgradeable, ERC721EnumerableUpgradeable {
    IERC721MetadataUpgradeable private _nft;
    INftVault public nftVault;

    // Mapping from staker to list of staked token IDs
    mapping(address => mapping(uint256 => uint256)) private _stakedTokens;

    // Mapping from token ID to index of the staker tokens list
    mapping(uint256 => uint256) private _stakedTokensIndex;

    // Mapping from staker to total staked amount of tokens
    mapping(address => uint256) public totalStaked;

    string private _customBaseURI;

    mapping(address => bool) private _authorized;

    IBNFTRegistry public bnftRegistry;

    modifier onlyAuthorized() {
        require(_authorized[msg.sender], "StNft: caller is not authorized");
        _;
    }

    function __StNft_init(
        IERC721MetadataUpgradeable nft_,
        INftVault nftVault_,
        string memory name_,
        string memory symbol_
    ) internal onlyInitializing {
        __Ownable_init();
        __ReentrancyGuard_init();
        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();

        _nft = nft_;
        nftVault = nftVault_;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165Upgradeable, ERC721EnumerableUpgradeable) returns (bool) {
        return interfaceId == type(IStakedNft).interfaceId || super.supportsInterface(interfaceId);
    }

    function setBnftRegistry(address bnftRegistry_) external override onlyOwner {
        require(bnftRegistry_ != address(0), "StNft: invalid bnft registry");
        bnftRegistry = IBNFTRegistry(bnftRegistry_);
    }

    function authorise(address addr_, bool authorized_) external override onlyOwner {
        _authorized[addr_] = authorized_;
    }

    function mint(address to_, uint256[] calldata tokenIds_) external override onlyAuthorized nonReentrant {
        address staker_ = msg.sender;
        uint256 tokenId_;

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            require(_nft.ownerOf(tokenId_) == address(nftVault), "StNft: underlying owner not vault");
        }

        nftVault.depositNft(address(_nft), tokenIds_, staker_);

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            _addTokenToStakerEnumeration(staker_, tokenId_);
            _safeMint(to_, tokenId_);
        }

        emit Minted(to_, tokenIds_);
    }

    function burn(address from_, uint256[] calldata tokenIds_) external override onlyAuthorized nonReentrant {
        uint256 tokenId_;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];

            require(from_ == ownerOf(tokenId_), "stNft: only owner can burn");
            require(address(nftVault) == _nft.ownerOf(tokenId_), "stNft: underlying owner not vault");

            _removeTokenFromStakerEnumeration(stakerOf(tokenId_), tokenId_);
            _burn(tokenId_);
        }

        nftVault.withdrawNft(address(_nft), tokenIds_);

        emit Burned(from_, tokenIds_);
    }

    function stakerOf(uint256 tokenId_) public view override returns (address) {
        return nftVault.stakerOf(address(_nft), tokenId_);
    }

    function _addTokenToStakerEnumeration(address staker_, uint256 tokenId_) private {
        uint256 length = totalStaked[staker_];
        _stakedTokens[staker_][length] = tokenId_;
        _stakedTokensIndex[tokenId_] = length;
        totalStaked[staker_] += 1;
    }

    function _removeTokenFromStakerEnumeration(address staker_, uint256 tokenId_) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = totalStaked[staker_] - 1;
        uint256 tokenIndex = _stakedTokensIndex[tokenId_];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _stakedTokens[staker_][lastTokenIndex];

            _stakedTokens[staker_][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _stakedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _stakedTokensIndex[tokenId_];
        delete _stakedTokens[staker_][lastTokenIndex];
        totalStaked[staker_] -= 1;
    }

    function tokenOfStakerByIndex(address staker_, uint256 index) external view override returns (uint256) {
        require(index < totalStaked[staker_], "stNft: staker index out of bounds");
        return _stakedTokens[staker_][index];
    }

    function underlyingAsset() external view override returns (address) {
        return address(_nft);
    }

    function setBaseURI(string memory baseURI_) public onlyOwner {
        _customBaseURI = baseURI_;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _customBaseURI;
    }

    function tokenURI(
        uint256 tokenId_
    ) public view override(ERC721Upgradeable, IERC721MetadataUpgradeable) returns (string memory) {
        if (bytes(_customBaseURI).length > 0) {
            return super.tokenURI(tokenId_);
        }

        return _nft.tokenURI(tokenId_);
    }

    function _approve(address to, uint256 tokenId) internal virtual override(ERC721Upgradeable) {
        to;
        tokenId;

        revert("stNft: approve not allowed");
    }

    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual override(ERC721Upgradeable) {
        owner;
        operator;
        approved;

        revert("stNft: approve not allowed");
    }

    function _transfer(address from, address to, uint256 tokenId) internal virtual override(ERC721Upgradeable) {
        from;
        to;
        tokenId;

        revert("stNft: transfer not allowed");
    }

    function setDelegateCash(address delegate_, uint256[] calldata tokenIds_, bool value_) external override {
        address tokenOwner_;
        uint256 tokenId_;
        (address bnftProxy, ) = bnftRegistry.getBNFTAddresses(address(this));
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            tokenOwner_ = ownerOf(tokenId_);
            if (tokenOwner_ != msg.sender && bnftProxy != address(0) && tokenOwner_ == bnftProxy) {
                tokenOwner_ = IERC721Upgradeable(bnftProxy).ownerOf(tokenId_);
            }
            require(msg.sender == tokenOwner_, "stNft: only owner can delegate");
        }
        nftVault.setDelegateCash(delegate_, address(_nft), tokenIds_, value_);
    }

    function getDelegateCashForToken(
        uint256[] calldata tokenIds_
    ) external view override returns (address[][] memory delegates) {
        return nftVault.getDelegateCashForToken(address(_nft), tokenIds_);
    }

    function setDelegateCashV2(address delegate_, uint256[] calldata tokenIds_, bool value_) external override {
        address tokenOwner_;
        uint256 tokenId_;
        (address bnftProxy, ) = bnftRegistry.getBNFTAddresses(address(this));
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            tokenOwner_ = ownerOf(tokenId_);
            if (tokenOwner_ != msg.sender && bnftProxy != address(0) && tokenOwner_ == bnftProxy) {
                tokenOwner_ = IERC721Upgradeable(bnftProxy).ownerOf(tokenId_);
            }
            require(msg.sender == tokenOwner_, "stNft: only owner can delegate");
        }
        nftVault.setDelegateCashV2(delegate_, address(_nft), tokenIds_, value_);
    }

    function getDelegateCashForTokenV2(
        uint256[] calldata tokenIds_
    ) external view override returns (address[][] memory delegates) {
        return nftVault.getDelegateCashForTokenV2(address(_nft), tokenIds_);
    }
}
