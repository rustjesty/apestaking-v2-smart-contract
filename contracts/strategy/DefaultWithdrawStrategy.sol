// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IApeCoinStaking} from "../interfaces/IApeCoinStaking.sol";
import {INftVault} from "../interfaces/INftVault.sol";
import {ICoinPool} from "../interfaces/ICoinPool.sol";
import {INftPool} from "../interfaces/INftPool.sol";
import {IStakeManager} from "../interfaces/IStakeManager.sol";
import {IWithdrawStrategy} from "../interfaces/IWithdrawStrategy.sol";

import {ApeStakingLib} from "../libraries/ApeStakingLib.sol";

contract DefaultWithdrawStrategy is IWithdrawStrategy, ReentrancyGuard, Ownable {
    using ApeStakingLib for IApeCoinStaking;
    using SafeCast for uint256;
    using SafeCast for uint248;

    IApeCoinStaking public apeCoinStaking;
    IERC20 public wrapApeCoin;
    IStakeManager public staker;
    ICoinPool public coinPool;
    INftVault public nftVault;

    address public bayc;
    address public mayc;
    address public bakc;

    modifier onlyStaker() {
        require(msg.sender == address(staker), "DWS: caller is not staker");
        _;
    }

    constructor(
        IApeCoinStaking apeCoinStaking_,
        INftVault nftVault_,
        ICoinPool coinPool_,
        IStakeManager staker_
    ) Ownable() {
        apeCoinStaking = apeCoinStaking_;
        nftVault = nftVault_;
        coinPool = coinPool_;
        staker = staker_;

        wrapApeCoin = IERC20(coinPool.getWrapApeCoin());
        bayc = address(apeCoinStaking.bayc());
        mayc = address(apeCoinStaking.mayc());
        bakc = address(apeCoinStaking.bakc());
    }

    function setApeCoinStaking(address apeCoinStaking_) public onlyOwner {
        apeCoinStaking = IApeCoinStaking(apeCoinStaking_);

        bayc = address(apeCoinStaking.bayc());
        mayc = address(apeCoinStaking.mayc());
        bakc = address(apeCoinStaking.bakc());
    }

    function initGlobalState() public onlyStaker {
        wrapApeCoin = IERC20(coinPool.getWrapApeCoin());
    }

    struct WithdrawApeCoinVars {
        uint256 tokenId;
        uint256 stakedApeCoin;
        uint256 pendingRewards;
        uint256 unstakeNftSize;
        uint256 totalWithdrawn;
    }

    function withdrawApeCoin(uint256 required) external override onlyStaker returns (uint256 withdrawn) {
        require(address(wrapApeCoin) != address(0), "DWS: wrapApeCoin not set");

        WithdrawApeCoinVars memory vars;

        // 1. withdraw refund

        // 2. claim ape coin pool

        // 3. unstake ape coin pool

        // 4. unstake bayc
        if (vars.totalWithdrawn < required) {
            vars.stakedApeCoin = staker.stakedApeCoin(ApeStakingLib.BAYC_POOL_ID);
            if (vars.stakedApeCoin > 0) {
                vars.tokenId = 0;
                vars.unstakeNftSize = 0;
                vars.stakedApeCoin = 0;
                vars.pendingRewards = 0;
                for (uint256 i = 0; i < nftVault.totalStakingNft(bayc, address(staker)); i++) {
                    vars.tokenId = nftVault.stakingNftIdByIndex(bayc, address(staker), i);
                    vars.stakedApeCoin = apeCoinStaking
                        .nftPosition(ApeStakingLib.BAYC_POOL_ID, vars.tokenId)
                        .stakedAmount;

                    vars.pendingRewards = apeCoinStaking.pendingRewards(ApeStakingLib.BAYC_POOL_ID, vars.tokenId);
                    vars.pendingRewards -= staker.calculateFee(vars.pendingRewards);

                    vars.totalWithdrawn += vars.stakedApeCoin;
                    vars.totalWithdrawn += vars.pendingRewards;
                    vars.unstakeNftSize += 1;

                    if (vars.totalWithdrawn >= required) {
                        break;
                    }
                }
                if (vars.unstakeNftSize > 0) {
                    uint256[] memory tokenIds = new uint256[](vars.unstakeNftSize);
                    for (uint256 i = 0; i < vars.unstakeNftSize; i++) {
                        tokenIds[i] = nftVault.stakingNftIdByIndex(bayc, address(staker), i);
                    }
                    staker.unstakeBayc(tokenIds);
                }
            }
        }

        // 5. unstake mayc
        if (vars.totalWithdrawn < required) {
            vars.stakedApeCoin = staker.stakedApeCoin(ApeStakingLib.MAYC_POOL_ID);
            if (vars.stakedApeCoin > 0) {
                vars.tokenId = 0;
                vars.unstakeNftSize = 0;
                vars.stakedApeCoin = 0;
                vars.pendingRewards = 0;
                for (uint256 i = 0; i < nftVault.totalStakingNft(mayc, address(staker)); i++) {
                    vars.tokenId = nftVault.stakingNftIdByIndex(mayc, address(staker), i);
                    vars.stakedApeCoin = apeCoinStaking
                        .nftPosition(ApeStakingLib.MAYC_POOL_ID, vars.tokenId)
                        .stakedAmount;

                    vars.pendingRewards = apeCoinStaking.pendingRewards(ApeStakingLib.MAYC_POOL_ID, vars.tokenId);
                    vars.pendingRewards -= staker.calculateFee(vars.pendingRewards);

                    vars.totalWithdrawn += vars.stakedApeCoin;
                    vars.totalWithdrawn += vars.pendingRewards;

                    vars.unstakeNftSize += 1;

                    if (vars.totalWithdrawn >= required) {
                        break;
                    }
                }
                if (vars.unstakeNftSize > 0) {
                    uint256[] memory tokenIds = new uint256[](vars.unstakeNftSize);
                    for (uint256 i = 0; i < vars.unstakeNftSize; i++) {
                        tokenIds[i] = nftVault.stakingNftIdByIndex(mayc, address(staker), i);
                    }
                    staker.unstakeMayc(tokenIds);
                }
            }
        }

        // 6. unstake bakc
        if (vars.totalWithdrawn < required) {
            vars.stakedApeCoin = staker.stakedApeCoin(ApeStakingLib.BAKC_POOL_ID);
            if (vars.stakedApeCoin > 0) {
                vars.tokenId = 0;
                vars.unstakeNftSize = 0;
                vars.stakedApeCoin = 0;
                vars.pendingRewards = 0;
                for (uint256 i = 0; i < nftVault.totalStakingNft(bakc, address(staker)); i++) {
                    vars.tokenId = nftVault.stakingNftIdByIndex(bakc, address(staker), i);
                    vars.stakedApeCoin = apeCoinStaking
                        .nftPosition(ApeStakingLib.BAKC_POOL_ID, vars.tokenId)
                        .stakedAmount;

                    vars.pendingRewards = apeCoinStaking.pendingRewards(ApeStakingLib.BAKC_POOL_ID, vars.tokenId);
                    vars.pendingRewards -= staker.calculateFee(vars.pendingRewards);

                    vars.totalWithdrawn += vars.stakedApeCoin;
                    vars.totalWithdrawn += vars.pendingRewards;
                    vars.unstakeNftSize += 1;

                    if (vars.totalWithdrawn >= required) {
                        break;
                    }
                }
                if (vars.unstakeNftSize > 0) {
                    uint256[] memory tokenIds = new uint256[](vars.unstakeNftSize);
                    for (uint256 i = 0; i < vars.unstakeNftSize; i++) {
                        tokenIds[i] = nftVault.stakingNftIdByIndex(bakc, address(staker), i);
                    }
                    staker.unstakeBakc(tokenIds);
                }
            }
        }

        // Caution: unstake nfts are asynchronous, the balance in our pool maybe not changed
        withdrawn = vars.totalWithdrawn;
    }
}
