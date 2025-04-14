// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {IDelegateRegistryV2} from "./interfaces/IDelegateRegistryV2.sol";

/// @title BendNftLockup
/// @author BendDAO
/// @notice Bend NFT Lockup contract
/// @dev This contract is used to lock up APE NFTs for BendDAO on ETH Mainnet
contract BendNftLockup is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    event NftDeposited(address indexed nft, uint256[] tokenIds, address indexed owner);
    event NftWithdrawn(address indexed nft, uint256[] tokenIds, address indexed owner);
    event NftFinalized(address indexed nft, uint256[] tokenIds, address indexed owner);

    address public botAdmin;
    address public nftValut;
    IDelegateRegistryV2 public delegationRegistryV2;
    bytes32 public nftShadowRights;
    address public bayc;
    address public mayc;
    address public bakc;

    uint40 public constant MAX_OP_INTERVAL = 1 hours;
    uint8 public constant STATUS_INIT = 0;
    uint8 public constant STATUS_WITHDRAWING = 1;

    struct TokenData {
        address owner;
        uint40 lastOpTime;
        uint8 status;
    }
    mapping(address => mapping(uint256 => TokenData)) public nftTokenDatas;

    modifier onlyBot() {
        require(msg.sender == botAdmin, "BendNftLockup: caller not bot admin");
        _;
    }

    modifier onlyApes(address[] calldata nfts_) {
        _onlyApes(nfts_);
        _;
    }

    function _onlyApes(address[] calldata nfts_) internal view {
        address nft_;
        for (uint256 i = 0; i < nfts_.length; i++) {
            nft_ = nfts_[i];
            require(bayc == nft_ || mayc == nft_ || bakc == nft_, "BendNftLockup: not ape");
        }
    }

    function initialize(
        address nftValut_,
        address bayc_,
        address mayc_,
        address bakc_,
        address delegationRegistryV2_
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        nftValut = nftValut_; // It's a vault address on ApeChain, not ETH Mainnet
        nftShadowRights = 0x000000000000000000000000000000000000000000000000000000ffffffffff;
        delegationRegistryV2 = IDelegateRegistryV2(delegationRegistryV2_);

        bayc = bayc_;
        mayc = mayc_;
        bakc = bakc_;
    }

    function deposit(
        address[] calldata nfts_,
        uint256[][] calldata tokenIds_
    ) public nonReentrant whenNotPaused onlyApes(nfts_) {
        require(nfts_.length == tokenIds_.length, "BendNftLockup: length not match");
        require(nftValut != address(0), "BendNftLockup: vault not set");
        require(address(delegationRegistryV2) != address(0), "BendNftLockup: delegationRegistryV2 not set");

        address nft_;
        uint256 tokenId_;
        for (uint256 i = 0; i < nfts_.length; i++) {
            nft_ = nfts_[i];
            require(tokenIds_[i].length > 0, "BendNftLockup: token length zero");

            for (uint256 j = 0; j < tokenIds_[i].length; j++) {
                tokenId_ = tokenIds_[i][j];
                TokenData storage tokenData = nftTokenDatas[nft_][tokenId_];
                require(tokenData.status == STATUS_INIT, "BendNftLockup: status not init");
                require(
                    uint40(block.timestamp) > (tokenData.lastOpTime + MAX_OP_INTERVAL),
                    "BendNftLockup: interval not enough"
                );

                IERC721Upgradeable(nft_).transferFrom(msg.sender, address(this), tokenId_);

                tokenData.owner = msg.sender;
                tokenData.lastOpTime = uint40(block.timestamp);

                delegationRegistryV2.delegateERC721(nftValut, nft_, tokenId_, nftShadowRights, true);
            }

            emit NftDeposited(nft_, tokenIds_[i], msg.sender);
        }
    }

    function withdraw(
        address[] calldata nfts_,
        uint256[][] calldata tokenIds_
    ) public nonReentrant whenNotPaused onlyApes(nfts_) {
        require(nfts_.length == tokenIds_.length, "BendNftLockup: length not match");

        address nft_;
        uint256 tokenId_;
        for (uint256 i = 0; i < nfts_.length; i++) {
            nft_ = nfts_[i];
            require(tokenIds_[i].length > 0, "BendNftLockup: token length zero");

            for (uint256 j = 0; j < tokenIds_[i].length; j++) {
                tokenId_ = tokenIds_[i][j];

                require(IERC721Upgradeable(nft_).ownerOf(tokenId_) == address(this), "BendNftLockup: invalid owner");

                TokenData storage tokenData = nftTokenDatas[nft_][tokenId_];
                require(tokenData.owner == msg.sender, "BendNftLockup: caller not owner");
                require(tokenData.status == STATUS_INIT, "BendNftLockup: status not init");
                require(
                    uint40(block.timestamp) > (tokenData.lastOpTime + MAX_OP_INTERVAL),
                    "BendNftLockup: interval not enough"
                );

                tokenData.status = STATUS_WITHDRAWING;
                tokenData.lastOpTime = uint40(block.timestamp);
            }

            emit NftWithdrawn(nft_, tokenIds_[i], msg.sender);
        }
    }

    /// @dev Only bot can call this function and bot MUST enusre the token staking on ApeChain has been unstaked
    function finalize(
        address[] calldata nfts_,
        uint256[][] calldata tokenIds_,
        address owner_
    ) public nonReentrant whenNotPaused onlyBot onlyApes(nfts_) {
        require(nfts_.length == tokenIds_.length, "BendNftLockup: length not match");

        address nft_;
        uint256 tokenId_;
        for (uint256 i = 0; i < nfts_.length; i++) {
            nft_ = nfts_[i];
            require(tokenIds_[i].length > 0, "BendNftLockup: token length zero");

            for (uint256 j = 0; j < tokenIds_[i].length; j++) {
                tokenId_ = tokenIds_[i][j];
                require(IERC721Upgradeable(nft_).ownerOf(tokenId_) == address(this), "BendNftLockup: invalid owner");

                TokenData storage tokenData = nftTokenDatas[nft_][tokenId_];
                require(tokenData.owner == owner_, "BendNftLockup: owner not match");
                require(tokenData.status == STATUS_WITHDRAWING, "BendNftLockup: status not withdrawing");

                delegationRegistryV2.delegateERC721(nftValut, nft_, tokenId_, nftShadowRights, false);

                tokenData.status = STATUS_INIT;
                tokenData.lastOpTime = uint40(block.timestamp);
                IERC721Upgradeable(nft_).transferFrom(address(this), owner_, tokenId_);
            }

            emit NftFinalized(nft_, tokenIds_[i], owner_);
        }
    }

    function getNftTokenData(address nft_, uint256 tokenId_) public view returns (TokenData memory tokenData) {
        return nftTokenDatas[nft_][tokenId_];
    }

    function getBotAdmin() public view returns (address) {
        return botAdmin;
    }

    function setBotAdmin(address botAdmin_) public onlyOwner {
        require(botAdmin_ != address(0), "BendNftLockup: invalid address");
        botAdmin = botAdmin_;
    }

    function setDelegationRegistryV2(address delegationRegistryV2_) public onlyOwner {
        require(delegationRegistryV2_ != address(0), "BendNftLockup: invalid address");
        delegationRegistryV2 = IDelegateRegistryV2(delegationRegistryV2_);
    }

    function setNftShadowRights(bytes32 nftShadowRights_) public onlyOwner {
        nftShadowRights = nftShadowRights_;
    }

    function setPause(bool flag) public onlyOwner {
        if (flag) {
            _pause();
        } else {
            _unpause();
        }
    }

    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        require((bayc == msg.sender || mayc == msg.sender || bakc == msg.sender), "BendNftLockup: not ape nft");
        return this.onERC721Received.selector;
    }
}
