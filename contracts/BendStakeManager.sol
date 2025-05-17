// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {IStakeManager, IApeCoinStaking} from "./interfaces/IStakeManager.sol";
import {INftVault} from "./interfaces/INftVault.sol";
import {ICoinPool} from "./interfaces/ICoinPool.sol";
import {INftPool} from "./interfaces/INftPool.sol";
import {IStakedNft} from "./interfaces/IStakedNft.sol";
import {IRewardsStrategy} from "./interfaces/IRewardsStrategy.sol";
import {IWithdrawStrategy} from "./interfaces/IWithdrawStrategy.sol";
import {IWAPE} from "./interfaces/IWAPE.sol";

import {ApeStakingLib} from "./libraries/ApeStakingLib.sol";

contract BendStakeManager is IStakeManager, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using ApeStakingLib for IApeCoinStaking;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for uint248;
    using SafeCastUpgradeable for uint128;

    uint256 public constant PERCENTAGE_FACTOR = 1e4;
    uint256 public constant MAX_FEE = 1000;
    uint256 public constant MAX_PENDING_FEE = 100 * 1e18;

    struct StakerStorageUI {
        IWithdrawStrategy withdrawStrategy;
        uint256 fee;
        address feeRecipient;
        uint256 pendingFeeAmount;
        uint256 apeCoinPoolStakedAmount;
        IApeCoinStaking apeCoinStaking;
        IERC20Upgradeable wrapApeCoin;
        INftVault nftVault;
        ICoinPool coinPool;
        INftPool nftPool;
        IStakedNft stBayc;
        IStakedNft stMayc;
        IStakedNft stBakc;
        address bayc;
        address mayc;
        address bakc;
        address botAdmin;
    }
    struct StakerStorage {
        mapping(address => IRewardsStrategy) rewardsStrategies;
        IWithdrawStrategy withdrawStrategy;
        uint256 fee;
        address feeRecipient;
        uint256 pendingFeeAmount;
        uint256 apeCoinPoolStakedAmount;
        IApeCoinStaking apeCoinStaking;
        IERC20Upgradeable wrapApeCoin;
        INftVault nftVault;
        ICoinPool coinPool;
        INftPool nftPool;
        IStakedNft stBayc;
        IStakedNft stMayc;
        IStakedNft stBakc;
        address bayc;
        address mayc;
        address bakc;
        address botAdmin;
        mapping(address => PendingFund) pendingFunds;
    }
    struct PendingFund {
        uint256 principal;
        uint256 nftRewards;
        uint256 coinRewards;
    }
    StakerStorage internal _stakerStorage;

    modifier onlyBot() {
        require(msg.sender == _stakerStorage.botAdmin, "BendStakeManager: caller is not bot admin");
        _;
    }

    modifier onlyApe(address nft_) {
        require(
            nft_ == _stakerStorage.bayc || nft_ == _stakerStorage.mayc || nft_ == _stakerStorage.bakc,
            "BendStakeManager: nft must be ape"
        );
        _;
    }

    modifier onlyCoinPool() {
        require(msg.sender == address(_stakerStorage.coinPool), "BendStakeManager: caller is not coin pool");
        _;
    }

    modifier onlyNftPool() {
        require(msg.sender == address(_stakerStorage.nftPool), "BendStakeManager: caller is not nft pool");
        _;
    }

    modifier onlyWithdrawStrategyOrBot() {
        require(
            (msg.sender == address(_stakerStorage.withdrawStrategy)) || (msg.sender == _stakerStorage.botAdmin),
            "BendStakeManager: caller is not authorized"
        );
        _;
    }

    function initialize(
        IApeCoinStaking apeStaking_,
        ICoinPool coinPool_,
        INftPool nftPool_,
        INftVault nftVault_,
        IStakedNft stBayc_,
        IStakedNft stMayc_,
        IStakedNft stBakc_
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        _stakerStorage.apeCoinStaking = apeStaking_;
        _stakerStorage.coinPool = coinPool_;
        _stakerStorage.nftPool = nftPool_;
        _stakerStorage.nftVault = nftVault_;
        _stakerStorage.wrapApeCoin = IERC20Upgradeable(_stakerStorage.coinPool.getWrapApeCoin());

        _stakerStorage.wrapApeCoin.approve(address(_stakerStorage.apeCoinStaking), type(uint256).max);
        _stakerStorage.wrapApeCoin.approve(address(_stakerStorage.coinPool), type(uint256).max);
        _stakerStorage.wrapApeCoin.approve(address(_stakerStorage.nftPool), type(uint256).max);
        _stakerStorage.wrapApeCoin.approve(address(_stakerStorage.nftVault), type(uint256).max);

        _stakerStorage.stBayc = stBayc_;
        _stakerStorage.stMayc = stMayc_;
        _stakerStorage.stBakc = stBakc_;

        _stakerStorage.bayc = stBayc_.underlyingAsset();
        _stakerStorage.mayc = stMayc_.underlyingAsset();
        _stakerStorage.bakc = stBakc_.underlyingAsset();

        IERC721Upgradeable(_stakerStorage.bayc).setApprovalForAll(address(_stakerStorage.stBayc), true);
        IERC721Upgradeable(_stakerStorage.mayc).setApprovalForAll(address(_stakerStorage.stMayc), true);
        IERC721Upgradeable(_stakerStorage.bakc).setApprovalForAll(address(_stakerStorage.stBakc), true);
    }

    function setApeCoinStaking(address apeCoinStaking_) public onlyOwner {
        _stakerStorage.apeCoinStaking = IApeCoinStaking(apeCoinStaking_);
        _stakerStorage.wrapApeCoin.approve(address(_stakerStorage.apeCoinStaking), type(uint256).max);
    }

    function getStakerStorageUI() public view returns (StakerStorageUI memory) {
        StakerStorageUI memory stakerStorageUI;
        stakerStorageUI.withdrawStrategy = _stakerStorage.withdrawStrategy;
        stakerStorageUI.fee = _stakerStorage.fee;
        stakerStorageUI.feeRecipient = _stakerStorage.feeRecipient;
        stakerStorageUI.pendingFeeAmount = _stakerStorage.pendingFeeAmount;
        stakerStorageUI.apeCoinPoolStakedAmount = _stakerStorage.apeCoinPoolStakedAmount;
        stakerStorageUI.apeCoinStaking = _stakerStorage.apeCoinStaking;
        stakerStorageUI.wrapApeCoin = _stakerStorage.wrapApeCoin;
        stakerStorageUI.nftVault = _stakerStorage.nftVault;
        stakerStorageUI.coinPool = _stakerStorage.coinPool;
        stakerStorageUI.nftPool = _stakerStorage.nftPool;
        stakerStorageUI.stBayc = _stakerStorage.stBayc;
        stakerStorageUI.stMayc = _stakerStorage.stMayc;
        stakerStorageUI.stBakc = _stakerStorage.stBakc;
        stakerStorageUI.bayc = _stakerStorage.bayc;
        stakerStorageUI.mayc = _stakerStorage.mayc;
        stakerStorageUI.bakc = _stakerStorage.bakc;
        stakerStorageUI.botAdmin = _stakerStorage.botAdmin;
        return stakerStorageUI;
    }

    function getPendingFund(address nft_) public view returns (PendingFund memory) {
        return _stakerStorage.pendingFunds[nft_];
    }

    receive() external payable {
        require(
            (msg.sender == address(_stakerStorage.wrapApeCoin) ||
                (msg.sender == address(_stakerStorage.apeCoinStaking))),
            "BendStakeManager: invalid sender"
        );
    }

    function stBayc() external view override returns (IStakedNft) {
        return _stakerStorage.stBayc;
    }

    function stMayc() external view override returns (IStakedNft) {
        return _stakerStorage.stMayc;
    }

    function stBakc() external view override returns (IStakedNft) {
        return _stakerStorage.stBakc;
    }

    function fee() external view override returns (uint256) {
        return _stakerStorage.fee;
    }

    function feeRecipient() external view override returns (address) {
        return _stakerStorage.feeRecipient;
    }

    function updateFee(uint256 fee_) external onlyOwner {
        require(fee_ <= MAX_FEE, "BendStakeManager: invalid fee");
        _stakerStorage.fee = fee_;
        emit FeeRatioChanged(fee_);
    }

    function updateFeeRecipient(address recipient_) external onlyOwner {
        require(recipient_ != address(0), "BendStakeManager: invalid fee recipient");
        _stakerStorage.feeRecipient = recipient_;
        emit FeeRecipientChanged(recipient_);
    }

    function botAdmin() external view returns (address) {
        return _stakerStorage.botAdmin;
    }

    function updateBotAdmin(address botAdmin_) external override onlyOwner {
        require(botAdmin_ != address(0), "BendStakeManager: invalid bot admin");
        _stakerStorage.botAdmin = botAdmin_;
        emit BotAdminChanged(botAdmin_);
    }

    function updateRewardsStrategy(
        address nft_,
        IRewardsStrategy rewardsStrategy_
    ) external override onlyOwner onlyApe(nft_) {
        require(address(rewardsStrategy_) != address(0), "BendStakeManager: invalid reward strategy");
        _stakerStorage.rewardsStrategies[nft_] = rewardsStrategy_;
        emit RewardsStrategyChanged(nft_, address(rewardsStrategy_));
    }

    function rewardsStrategies(address nft_) external view returns (IRewardsStrategy) {
        return _stakerStorage.rewardsStrategies[nft_];
    }

    function getNftRewardsShare(address nft_) external view returns (uint256 nftShare) {
        require(
            address(_stakerStorage.rewardsStrategies[nft_]) != address(0),
            "BendStakeManager: invalid reward strategy"
        );
        nftShare = _stakerStorage.rewardsStrategies[nft_].getNftRewardsShare();
    }

    function updateWithdrawStrategy(IWithdrawStrategy withdrawStrategy_) external override onlyOwner {
        require(address(withdrawStrategy_) != address(0), "BendStakeManager: invalid withdraw strategy");
        _stakerStorage.withdrawStrategy = withdrawStrategy_;
        withdrawStrategy_.initGlobalState();
        emit WithdrawStrategyChanged(address(withdrawStrategy_));
    }

    function _calculateFee(uint256 rewardsAmount_) internal view returns (uint256 feeAmount) {
        return rewardsAmount_.mulDiv(_stakerStorage.fee, PERCENTAGE_FACTOR, MathUpgradeable.Rounding.Down);
    }

    function calculateFee(uint256 rewardsAmount_) external view returns (uint256 feeAmount) {
        return _calculateFee(rewardsAmount_);
    }

    function _collectFee(uint256 rewardsAmount_) internal returns (uint256 feeAmount) {
        if (rewardsAmount_ > 0 && _stakerStorage.fee > 0) {
            feeAmount = _calculateFee(rewardsAmount_);
            _stakerStorage.pendingFeeAmount += feeAmount;
        }
    }

    function pendingFeeAmount() external view override returns (uint256) {
        return _stakerStorage.pendingFeeAmount;
    }

    function mintStNft(IStakedNft stNft_, address to_, uint256[] calldata tokenIds_) external onlyNftPool {
        stNft_.mint(to_, tokenIds_);
    }

    function burnStNft(IStakedNft stNft_, address from_, uint256[] calldata tokenIds_) external onlyNftPool {
        stNft_.burn(from_, tokenIds_);
    }

    function withdrawApeCoin(uint256 required) external override onlyCoinPool returns (uint256 withdrawn) {
        require(address(_stakerStorage.withdrawStrategy) != address(0), "BendStakeManager: invalid withdraw stratege");
        return _stakerStorage.withdrawStrategy.withdrawApeCoin(required);
    }

    function totalStakedApeCoin() external view override returns (uint256 amount) {
        amount += _stakedApeCoin(ApeStakingLib.APE_COIN_POOL_ID);
        amount += _stakedApeCoin(ApeStakingLib.BAYC_POOL_ID);
        amount += _stakedApeCoin(ApeStakingLib.MAYC_POOL_ID);
        amount += _stakedApeCoin(ApeStakingLib.BAKC_POOL_ID);
    }

    function totalPendingRewards() external view override returns (uint256 amount) {
        amount += _pendingRewards(ApeStakingLib.APE_COIN_POOL_ID);
        amount += _pendingRewards(ApeStakingLib.BAYC_POOL_ID);
        amount += _pendingRewards(ApeStakingLib.MAYC_POOL_ID);
        amount += _pendingRewards(ApeStakingLib.BAKC_POOL_ID);
        if (_stakerStorage.fee > 0) {
            amount -= _calculateFee(amount);
        }
    }

    function stakedApeCoin(uint256 poolId_) external view override returns (uint256) {
        return _stakedApeCoin(poolId_);
    }

    function _stakedApeCoin(uint256 poolId_) internal view returns (uint256) {
        if (poolId_ == ApeStakingLib.APE_COIN_POOL_ID) {
            return _stakerStorage.apeCoinPoolStakedAmount;
        }
        return
            _stakerStorage
                .nftVault
                .positionOf(_stakerStorage.apeCoinStaking.nftContracts(poolId_), address(this))
                .stakedAmount;
    }

    function _pendingRewards(uint256 poolId_) internal view returns (uint256) {
        if (poolId_ == ApeStakingLib.APE_COIN_POOL_ID) {
            // There's no ApeCoin Pool on ApeChain
            //return _stakerStorage.apeCoinStaking.pendingRewards(ApeStakingLib.APE_COIN_POOL_ID, 0);
            return 0;
        }
        return
            _stakerStorage.nftVault.pendingRewards(_stakerStorage.apeCoinStaking.nftContracts(poolId_), address(this));
    }

    function pendingRewards(uint256 poolId_) external view override returns (uint256 amount) {
        amount = _pendingRewards(poolId_);
        if (_stakerStorage.fee > 0) {
            amount -= _calculateFee(amount);
        }
    }

    function _prepareApeCoin(uint256 requiredAmount_) internal {
        _stakerStorage.coinPool.pullApeCoin(requiredAmount_);
    }

    function getNftPositionList(
        address[] calldata nfts_,
        uint256[][] calldata tokenIds_
    ) public view returns (uint256[][] memory stakedAmounts) {
        uint256 poolId_;
        address nft_;
        uint256 tokenId_;
        IApeCoinStaking.Position memory position_;

        require(nfts_.length == tokenIds_.length, "BendStakeManager: inconsistent length");

        stakedAmounts = new uint256[][](nfts_.length);
        for (uint256 i = 0; i < nfts_.length; i++) {
            nft_ = nfts_[i];
            poolId_ = _stakerStorage.apeCoinStaking.getNftPoolId(nft_);

            stakedAmounts[i] = new uint256[](tokenIds_[i].length);
            for (uint256 j = 0; j < tokenIds_[i].length; j++) {
                tokenId_ = tokenIds_[i][j];
                position_ = _stakerStorage.apeCoinStaking.nftPosition(poolId_, tokenId_);
                stakedAmounts[i][j] = position_.stakedAmount;
            }
        }

        return stakedAmounts;
    }

    // ApeCoin Pool which not exist on ApeChain

    // Desposit NFTs
    function depositNft(
        address[] calldata nfts_,
        uint256[][] calldata tokenIds_,
        address owner_
    ) public override onlyBot {
        _depositNft(nfts_, tokenIds_, owner_);
    }

    function _depositNft(address[] memory nfts_, uint256[][] memory tokenIds_, address owner_) internal {
        _stakerStorage.nftPool.deposit(nfts_, tokenIds_, owner_);
    }

    function withdrawNft(
        address[] calldata nfts_,
        uint256[][] calldata tokenIds_,
        address owner_
    ) public override onlyBot {
        _withdrawNft(nfts_, tokenIds_, owner_);
    }

    function _withdrawNft(address[] memory nfts_, uint256[][] memory tokenIds_, address owner_) internal {
        _stakerStorage.nftPool.withdraw(nfts_, tokenIds_, owner_);
    }

    // BAYC

    function _stakeBayc(uint256[] calldata tokenIds_) internal {
        uint256[] memory amounts_ = new uint256[](tokenIds_.length);
        uint256 maxCap = _stakerStorage.apeCoinStaking.getCurrentTimeRange(ApeStakingLib.BAYC_POOL_ID).capPerPosition;
        uint256 apeCoinAmount = 0;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            amounts_[i] = maxCap;
            apeCoinAmount += maxCap;
        }
        _prepareApeCoin(apeCoinAmount);
        _stakerStorage.nftVault.stakeBaycPool(tokenIds_, amounts_);
    }

    function stakeBayc(uint256[] calldata tokenIds_) external override onlyBot {
        _stakeBayc(tokenIds_);
    }

    function _unstakeBayc(uint256[] calldata tokenIds_) internal {
        uint256[] memory amounts_ = new uint256[](tokenIds_.length);
        address nft_ = _stakerStorage.bayc;

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            amounts_[i] = _stakerStorage.apeCoinStaking.getNftPosition(nft_, tokenIds_[i]).stakedAmount;
        }

        (uint256 principalAmount, uint256 rewardsAmount) = _stakerStorage.nftVault.unstakeBaycPool(
            tokenIds_,
            amounts_,
            address(this)
        );

        _distributePrincipalAndRewards(nft_, principalAmount, rewardsAmount);
    }

    function unstakeBayc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _unstakeBayc(tokenIds_);
    }

    function _claimBayc(uint256[] calldata tokenIds_) internal {
        address nft_ = _stakerStorage.bayc;
        uint256 rewardsAmount = _stakerStorage.nftVault.claimBaycPool(tokenIds_, address(this));

        _distributePrincipalAndRewards(nft_, 0, rewardsAmount);
    }

    function claimBayc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _claimBayc(tokenIds_);
    }

    // MAYC

    function _stakeMayc(uint256[] calldata tokenIds_) internal {
        uint256[] memory amounts_ = new uint256[](tokenIds_.length);
        uint256 maxCap = _stakerStorage.apeCoinStaking.getCurrentTimeRange(ApeStakingLib.MAYC_POOL_ID).capPerPosition;
        uint256 apeCoinAmount = 0;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            amounts_[i] = maxCap;
            apeCoinAmount += maxCap;
        }

        _prepareApeCoin(apeCoinAmount);
        _stakerStorage.nftVault.stakeMaycPool(tokenIds_, amounts_);
    }

    function stakeMayc(uint256[] calldata tokenIds_) external override onlyBot {
        _stakeMayc(tokenIds_);
    }

    function _unstakeMayc(uint256[] calldata tokenIds_) internal {
        uint256[] memory amounts_ = new uint256[](tokenIds_.length);
        address nft_ = _stakerStorage.mayc;

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            amounts_[i] = _stakerStorage.apeCoinStaking.getNftPosition(nft_, tokenIds_[i]).stakedAmount;
        }

        (uint256 principalAmount, uint256 rewardsAmount) = _stakerStorage.nftVault.unstakeMaycPool(
            tokenIds_,
            amounts_,
            address(this)
        );

        _distributePrincipalAndRewards(nft_, principalAmount, rewardsAmount);
    }

    function unstakeMayc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _unstakeMayc(tokenIds_);
    }

    function _claimMayc(uint256[] calldata tokenIds_) internal {
        address nft_ = _stakerStorage.mayc;
        uint256 rewardsAmount = _stakerStorage.nftVault.claimMaycPool(tokenIds_, address(this));

        _distributePrincipalAndRewards(nft_, 0, rewardsAmount);
    }

    function claimMayc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _claimMayc(tokenIds_);
    }

    // BAKC

    function _stakeBakc(uint256[] calldata tokenIds_) internal {
        uint256[] memory amounts_ = new uint256[](tokenIds_.length);
        uint256 maxCap = _stakerStorage.apeCoinStaking.getCurrentTimeRange(ApeStakingLib.BAKC_POOL_ID).capPerPosition;
        uint256 apeCoinAmount = 0;

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            amounts_[i] = maxCap;
            apeCoinAmount += maxCap;
        }

        _prepareApeCoin(apeCoinAmount);

        _stakerStorage.nftVault.stakeBakcPool(tokenIds_, amounts_);
    }

    function stakeBakc(uint256[] calldata tokenIds_) external override onlyBot {
        _stakeBakc(tokenIds_);
    }

    function _unstakeBakc(uint256[] calldata tokenIds_) internal {
        uint256[] memory amounts_ = new uint256[](tokenIds_.length);
        address nft_ = _stakerStorage.bakc;

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            amounts_[i] = _stakerStorage.apeCoinStaking.getNftPosition(nft_, tokenIds_[i]).stakedAmount;
        }

        (uint256 principalAmount, uint256 rewardsAmount) = _stakerStorage.nftVault.unstakeBakcPool(
            tokenIds_,
            amounts_,
            address(this)
        );

        _distributePrincipalAndRewards(nft_, principalAmount, rewardsAmount);
    }

    function unstakeBakc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _unstakeBakc(tokenIds_);
    }

    function _claimBakc(uint256[] calldata tokenIds_) internal {
        address nft_ = _stakerStorage.bakc;
        uint256 rewardsAmount = _stakerStorage.nftVault.claimBakcPool(tokenIds_, address(this));

        _distributePrincipalAndRewards(nft_, 0, rewardsAmount);
    }

    function claimBakc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _claimBakc(tokenIds_);
    }

    // Rewards

    function _distributePrincipalAndRewards(address nft_, uint256 principalAmount, uint256 rewardsAmount) internal {
        uint256 remainApeBalance = _stakerStorage.wrapApeCoin.balanceOf(address(this));
        if (remainApeBalance > _stakerStorage.pendingFeeAmount) {
            remainApeBalance = remainApeBalance - _stakerStorage.pendingFeeAmount;
        } else {
            remainApeBalance = 0;
        }

        remainApeBalance = _distributePrincipal(nft_, principalAmount, remainApeBalance);

        remainApeBalance = _distributeRewards(nft_, rewardsAmount, remainApeBalance);
    }

    function _distributePrincipal(
        address nft_,
        uint256 principalAmount,
        uint256 remainApeBalance
    ) internal returns (uint256) {
        if (principalAmount > 0) {
            _stakerStorage.pendingFunds[nft_].principal += principalAmount;
        }

        uint256 receivedAmount;
        if (remainApeBalance >= _stakerStorage.pendingFunds[nft_].principal) {
            receivedAmount = _stakerStorage.pendingFunds[nft_].principal;
        } else {
            receivedAmount = remainApeBalance;
        }
        if (receivedAmount > 0) {
            remainApeBalance -= receivedAmount;
            _stakerStorage.pendingFunds[nft_].principal -= receivedAmount;
            _stakerStorage.coinPool.receiveApeCoin(receivedAmount, 0);
        }

        return remainApeBalance;
    }

    function _distributeRewards(
        address nft_,
        uint256 rewardsAmount_,
        uint256 remainApeBalance
    ) internal returns (uint256) {
        require(
            address(_stakerStorage.rewardsStrategies[nft_]) != address(0),
            "BendStakeManager: reward strategy can't be zero address"
        );
        uint256 nftShare = _stakerStorage.rewardsStrategies[nft_].getNftRewardsShare();
        require(nftShare < PERCENTAGE_FACTOR, "BendStakeManager: nft share is too high");

        if (rewardsAmount_ > 0) {
            rewardsAmount_ -= _collectFee(rewardsAmount_);

            uint256 nftPoolRewards = rewardsAmount_.mulDiv(nftShare, PERCENTAGE_FACTOR, MathUpgradeable.Rounding.Down);
            uint256 apeCoinPoolRewards = rewardsAmount_ - nftPoolRewards;

            _stakerStorage.pendingFunds[nft_].nftRewards += nftPoolRewards;
            _stakerStorage.pendingFunds[nft_].coinRewards += apeCoinPoolRewards;
        }

        uint256 receivedAmount;

        // rewards for coin pool
        if (remainApeBalance >= _stakerStorage.pendingFunds[nft_].coinRewards) {
            receivedAmount = _stakerStorage.pendingFunds[nft_].coinRewards;
        } else {
            receivedAmount = remainApeBalance;
        }
        if (receivedAmount > 0) {
            remainApeBalance -= receivedAmount;
            _stakerStorage.pendingFunds[nft_].coinRewards -= receivedAmount;
            _stakerStorage.coinPool.receiveApeCoin(0, receivedAmount);
        }

        // rewards for nft pool
        if (remainApeBalance >= _stakerStorage.pendingFunds[nft_].nftRewards) {
            receivedAmount = _stakerStorage.pendingFunds[nft_].nftRewards;
        } else {
            receivedAmount = remainApeBalance;
        }
        if (receivedAmount > 0) {
            remainApeBalance -= receivedAmount;
            _stakerStorage.pendingFunds[nft_].nftRewards -= receivedAmount;
            _stakerStorage.nftPool.receiveApeCoin(nft_, receivedAmount);
        }

        return remainApeBalance;
    }

    function fixNftPendingFunds(
        address nft_,
        uint256 principal_,
        uint256 nftRewards_,
        uint256 coinRewards_
    ) external onlyOwner {
        _stakerStorage.pendingFunds[nft_].principal = principal_;
        _stakerStorage.pendingFunds[nft_].nftRewards = nftRewards_;
        _stakerStorage.pendingFunds[nft_].coinRewards = coinRewards_;
    }

    function fixPendingFeeAmount(uint256 pendingFeeAmount_) external onlyOwner {
        _stakerStorage.pendingFeeAmount = pendingFeeAmount_;
    }

    // Compound Methods

    function _compoudApeCoinPool() internal {
        _stakerStorage.coinPool.compoundApeCoin();
    }

    function compoudApeCoinPool() external onlyBot {
        _compoudApeCoinPool();
    }

    function _compoudNftPool() internal {
        _stakerStorage.nftPool.compoundApeCoin(_stakerStorage.bayc);
        _stakerStorage.nftPool.compoundApeCoin(_stakerStorage.mayc);
        _stakerStorage.nftPool.compoundApeCoin(_stakerStorage.bakc);
    }

    function compoudNftPool() external onlyBot {
        _compoudNftPool();
    }

    function _distributePendingFunds() internal {
        _stakerStorage.nftVault.withdrawPendingFunds(address(this));

        _distributePrincipalAndRewards(_stakerStorage.bayc, 0, 0);
        _distributePrincipalAndRewards(_stakerStorage.mayc, 0, 0);
        _distributePrincipalAndRewards(_stakerStorage.bakc, 0, 0);
    }

    function distributePendingFunds() external onlyBot {
        _distributePendingFunds();
    }

    // @dev Everyone can call this function to compound all pending funds
    function compoundPendingFunds() external nonReentrant {
        // compound native yield in ape coin pool
        _compoudApeCoinPool();

        // distribute pending funds in nft vault
        // which sent by the official ApeCoinStaking contract in async mode callback
        _distributePendingFunds();

        // compound ape coin in nft pool
        _compoudNftPool();
    }

    function compound(CompoundArgs calldata args_) external override nonReentrant onlyBot {
        uint256 claimedNfts;

        // compound native yield in ape coin pool
        _compoudApeCoinPool();

        // distribute pending funds in nft vault
        // which sent by the official ApeCoinStaking contract in async mode callback
        _distributePendingFunds();

        // claim rewards from NFT pool
        if (args_.claim.bayc.length > 0) {
            claimedNfts += args_.claim.bayc.length;
            _claimBayc(args_.claim.bayc);
        }
        if (args_.claim.mayc.length > 0) {
            claimedNfts += args_.claim.mayc.length;
            _claimMayc(args_.claim.mayc);
        }
        if (args_.claim.bakc.length > 0) {
            claimedNfts += args_.claim.bakc.length;
            _claimBakc(args_.claim.bakc);
        }

        // unstake some NFTs from NFT pool
        if (args_.unstake.bayc.length > 0) {
            _unstakeBayc(args_.unstake.bayc);
        }
        if (args_.unstake.mayc.length > 0) {
            _unstakeMayc(args_.unstake.mayc);
        }
        if (args_.unstake.bakc.length > 0) {
            _unstakeBakc(args_.unstake.bakc);
        }

        // withdraw some NFTs from NFT pool
        address[] memory nfts_ = new address[](1);
        uint256[][] memory tokenIds_ = new uint256[][](1);
        if (args_.withdraw.bayc.tokenIds.length > 0) {
            nfts_[0] = _stakerStorage.bayc;
            tokenIds_[0] = args_.withdraw.bayc.tokenIds;
            _withdrawNft(nfts_, tokenIds_, args_.withdraw.bayc.owner);
        }
        if (args_.withdraw.mayc.tokenIds.length > 0) {
            nfts_[0] = _stakerStorage.mayc;
            tokenIds_[0] = args_.withdraw.mayc.tokenIds;
            _withdrawNft(nfts_, tokenIds_, args_.withdraw.mayc.owner);
        }
        if (args_.withdraw.bakc.tokenIds.length > 0) {
            nfts_[0] = _stakerStorage.bakc;
            tokenIds_[0] = args_.withdraw.bakc.tokenIds;
            _withdrawNft(nfts_, tokenIds_, args_.withdraw.bakc.owner);
        }

        // deposit some NFTs to NFT pool
        if (args_.deposit.bayc.tokenIds.length > 0) {
            nfts_[0] = _stakerStorage.bayc;
            tokenIds_[0] = args_.deposit.bayc.tokenIds;
            _depositNft(nfts_, tokenIds_, args_.deposit.bayc.owner);
        }
        if (args_.deposit.mayc.tokenIds.length > 0) {
            nfts_[0] = _stakerStorage.mayc;
            tokenIds_[0] = args_.deposit.mayc.tokenIds;
            _depositNft(nfts_, tokenIds_, args_.deposit.mayc.owner);
        }
        if (args_.deposit.bakc.tokenIds.length > 0) {
            nfts_[0] = _stakerStorage.bakc;
            tokenIds_[0] = args_.deposit.bakc.tokenIds;
            _depositNft(nfts_, tokenIds_, args_.deposit.bakc.owner);
        }

        // stake some NFTs to NFT pool
        if (args_.stake.bayc.length > 0) {
            _stakeBayc(args_.stake.bayc);
        }
        if (args_.stake.mayc.length > 0) {
            _stakeMayc(args_.stake.mayc);
        }
        if (args_.stake.bakc.length > 0) {
            _stakeBakc(args_.stake.bakc);
        }

        // compound ape coin in nft pool
        _compoudNftPool();

        // transfer fee to recipient
        if (_stakerStorage.pendingFeeAmount > MAX_PENDING_FEE && _stakerStorage.feeRecipient != address(0)) {
            uint256 feeBalance = _stakerStorage.wrapApeCoin.balanceOf(address(this));
            if (feeBalance > _stakerStorage.pendingFeeAmount) {
                feeBalance = _stakerStorage.pendingFeeAmount;
            }
            _stakerStorage.wrapApeCoin.safeTransfer(_stakerStorage.feeRecipient, feeBalance);
            // solhint-disable-next-line
            _stakerStorage.pendingFeeAmount -= feeBalance;
        }

        emit Compounded(args_.claimCoinPool, claimedNfts);
    }
}
