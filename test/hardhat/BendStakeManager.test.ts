import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./setup";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { advanceHours, makeBN18, mintNft, randomUint, shuffledSubarray } from "./utils";
import { BigNumber, constants, Contract, ContractTransaction } from "ethers";
import { IApeCoinStaking, IRewardsStrategy, IStakeManager } from "../../typechain-types";
import { impersonateAccount, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import { parseEther } from "ethers/lib/utils";

makeSuite("BendStakeManager", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let owner: SignerWithAddress;
  let bot: SignerWithAddress;
  let feeRecipient: SignerWithAddress;
  let stakeManagerSigner: SignerWithAddress;
  let nftVaultSigner: SignerWithAddress;
  let fee: number;
  let lastRevert: string;
  let baycTokenIds: number[];
  let maycTokenIds: number[];
  let bakcTokenIds: number[];
  const APE_COIN_AMOUNT = 70000;

  before(async () => {
    owner = env.accounts[1];
    feeRecipient = env.feeRecipient;
    bot = env.accounts[3];
    fee = 500;
    baycTokenIds = [0, 1, 2, 3, 4, 5];
    await mintNft(owner, contracts.bayc, baycTokenIds);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);

    maycTokenIds = [6, 7, 8, 9, 10];
    await mintNft(owner, contracts.mayc, maycTokenIds);
    await contracts.mayc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);

    bakcTokenIds = [10, 11, 12, 13, 14];
    await mintNft(owner, contracts.bakc, bakcTokenIds);
    await contracts.bakc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);

    for (const baycId of baycTokenIds) {
      await contracts.bayc.connect(owner).transferFrom(owner.address, contracts.nftVault.address, baycId);
    }
    for (const maycId of maycTokenIds) {
      await contracts.mayc.connect(owner).transferFrom(owner.address, contracts.nftVault.address, maycId);
    }
    for (const bakcId of bakcTokenIds) {
      await contracts.bakc.connect(owner).transferFrom(owner.address, contracts.nftVault.address, bakcId);
    }

    await contracts.wrapApeCoin.connect(feeRecipient).deposit({ value: makeBN18(APE_COIN_AMOUNT) });
    await contracts.wrapApeCoin.connect(feeRecipient).approve(contracts.bendCoinPool.address, constants.MaxUint256);
    await contracts.bendCoinPool.connect(feeRecipient).deposit(makeBN18(APE_COIN_AMOUNT), owner.address);

    await contracts.wrapApeCoin.connect(owner).deposit({ value: makeBN18(APE_COIN_AMOUNT) });
    await contracts.wrapApeCoin.connect(owner).approve(contracts.bendCoinPool.address, constants.MaxUint256);
    await contracts.bendCoinPool.connect(owner).deposit(makeBN18(APE_COIN_AMOUNT), owner.address);

    await impersonateAccount(contracts.bendCoinPool.address);
    await setBalance(contracts.bendCoinPool.address, makeBN18(1000000));

    await impersonateAccount(contracts.bendStakeManager.address);
    stakeManagerSigner = await ethers.getSigner(contracts.bendStakeManager.address);
    await setBalance(stakeManagerSigner.address, makeBN18(100000));

    nftVaultSigner = await ethers.getSigner(contracts.nftVault.address);
    await impersonateAccount(contracts.nftVault.address);
    await setBalance(contracts.nftVault.address, makeBN18(100));

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });

  it("onlyApe: reverts", async () => {
    await expect(
      contracts.bendStakeManager.updateRewardsStrategy(constants.AddressZero, constants.AddressZero)
    ).revertedWith("BendStakeManager: nft must be ape");
  });

  it("onlyBot: reverts", async () => {
    const args: IStakeManager.CompoundArgsStruct = {
      claimCoinPool: true,
      deposit: {
        bayc: {
          tokenIds: [],
          owner: constants.AddressZero,
        },
        mayc: {
          tokenIds: [],
          owner: constants.AddressZero,
        },
        bakc: {
          tokenIds: [],
          owner: constants.AddressZero,
        },
      },
      withdraw: {
        bayc: {
          tokenIds: [],
          owner: constants.AddressZero,
        },
        mayc: {
          tokenIds: [],
          owner: constants.AddressZero,
        },
        bakc: {
          tokenIds: [],
          owner: constants.AddressZero,
        },
      },
      claim: {
        bayc: [],
        mayc: [],
        bakc: [],
      },
      unstake: {
        bayc: [],
        mayc: [],
        bakc: [],
      },
      stake: {
        bayc: [],
        mayc: [],
        bakc: [],
      },
      coinStakeThreshold: 0,
    };
    await expect(contracts.bendStakeManager.compound(args)).revertedWith("BendStakeManager: caller is not bot admin");
  });

  it("onlyCoinPool: reverts", async () => {
    await expect(contracts.bendStakeManager.withdrawApeCoin(constants.Zero)).revertedWith(
      "BendStakeManager: caller is not coin pool"
    );
  });

  it("onlyOwner: reverts", async () => {
    await expect(contracts.bendStakeManager.connect(owner).updateBotAdmin(constants.AddressZero)).revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(contracts.bendStakeManager.connect(owner).updateFee(constants.Zero)).revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(contracts.bendStakeManager.connect(owner).updateFeeRecipient(constants.AddressZero)).revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(
      contracts.bendStakeManager.connect(owner).updateRewardsStrategy(constants.AddressZero, constants.AddressZero)
    ).revertedWith("Ownable: caller is not the owner");
  });

  const excludeFee = (amount: BigNumber) => {
    return amount.sub(amount.mul(fee).div(10000));
  };

  it("updateFee", async () => {
    // expect(await contracts.bendStakeManager.fee()).eq(0);
    await expect(contracts.bendStakeManager.updateFee(1001)).revertedWith("BendStakeManager: invalid fee");
    await contracts.bendStakeManager.updateFee(fee);
    expect(await contracts.bendStakeManager.fee()).eq(fee);
    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("updateFeeRecipient", async () => {
    // expect(await contracts.bendStakeManager.feeRecipient()).eq(constants.AddressZero);
    await expect(contracts.bendStakeManager.updateFeeRecipient(constants.AddressZero)).revertedWith(
      "BendStakeManager: invalid fee recipient"
    );
    await contracts.bendStakeManager.updateFeeRecipient(feeRecipient.address);
    expect(await contracts.bendStakeManager.feeRecipient()).eq(feeRecipient.address);
    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("updateBotAdmin", async () => {
    // expect(await (contracts.bendStakeManager as Contract).botAdmin()).eq(constants.AddressZero);
    await contracts.bendStakeManager.updateBotAdmin(bot.address);
    expect(await (contracts.bendStakeManager as Contract).botAdmin()).eq(bot.address);
    // revert bot admin to default account to simple follow tests
    await contracts.bendStakeManager.updateBotAdmin(env.admin.address);
    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("updateRewardsStrategy", async () => {
    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.bayc.address)).eq(
      contracts.baycStrategy.address
    );

    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.mayc.address)).eq(
      contracts.maycStrategy.address
    );
    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.bakc.address)).eq(
      contracts.bakcStrategy.address
    );

    await contracts.bendStakeManager.updateRewardsStrategy(contracts.bayc.address, contracts.bayc.address);
    await contracts.bendStakeManager.updateRewardsStrategy(contracts.mayc.address, contracts.mayc.address);
    await contracts.bendStakeManager.updateRewardsStrategy(contracts.bakc.address, contracts.bakc.address);

    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.bayc.address)).eq(
      contracts.bayc.address
    );

    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.mayc.address)).eq(
      contracts.mayc.address
    );
    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.bakc.address)).eq(
      contracts.bakc.address
    );
  });

  it("prepareApeCoin: from pending ape coin only", async () => {
    const amount = makeBN18(randomUint(1, APE_COIN_AMOUNT - 1));
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();

    await expect(contracts.bendStakeManager.prepareApeCoin(amount)).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendStakeManager.address],
      [constants.Zero.sub(amount), amount]
    );
    expect(await contracts.bendCoinPool.pendingApeCoin()).eq(pendingApeCoin.sub(amount));
  });

  it("prepareApeCoin: from pending ape coin & rewards", async () => {
    await advanceHours(10);
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();
    const rewards = await contracts.bendStakeManager.pendingRewards(0);
    // const requiredAmount = pendingApeCoin.add(makeBN18(1));
    const requiredAmount = pendingApeCoin.sub(makeBN18(1));

    await expect(contracts.bendStakeManager.prepareApeCoin(requiredAmount)).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendStakeManager.address],
      [constants.Zero.sub(requiredAmount), requiredAmount]
    );
    expect(await contracts.bendCoinPool.pendingApeCoin()).eq(pendingApeCoin.add(rewards).sub(requiredAmount));
  });

  const expectStake = async (stakeAction: () => Promise<ContractTransaction>, requiredAmount: BigNumber) => {
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();
    const pendingRewards = await contracts.bendStakeManager.pendingRewards(0);
    const fee = 0;
    let changes = [];
    if (requiredAmount.lte(pendingApeCoin)) {
      // pending ape coin only
      changes = [constants.Zero.sub(requiredAmount), constants.Zero];
    } else if (requiredAmount.gt(pendingApeCoin) && pendingRewards.gte(requiredAmount.sub(pendingApeCoin))) {
      // pending ape coin & rewards
      changes = [pendingRewards.sub(requiredAmount), fee];
    } else {
      // pending ape coin & rewards & staked
      changes = [constants.Zero.sub(pendingApeCoin), fee];
    }
    return await expect(stakeAction()).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendStakeManager.address],
      changes
    );
  };

  it("depositNft", async () => {
    await contracts.bendStakeManager.depositNft(
      [contracts.bayc.address, contracts.mayc.address, contracts.bakc.address],
      [baycTokenIds, maycTokenIds, bakcTokenIds],
      owner.address
    );

    lastRevert = "depositNft";
    await snapshots.capture(lastRevert);
  });

  it("stakeBayc", async () => {
    await advanceHours(10);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(1);
    const requiredAmount = makeBN18(10094 * baycTokenIds.length);
    await expectStake(() => {
      return contracts.bendStakeManager.stakeBayc(baycTokenIds);
    }, requiredAmount);

    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(stakedAmount.add(requiredAmount));

    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(
      await contracts.apeStaking.stakedTotal(baycTokenIds, [], [])
    );

    lastRevert = "stakeBayc";
    await snapshots.capture(lastRevert);
  });

  it("claimBayc", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(1);
    let realRewards = constants.Zero;

    for (const id of baycTokenIds) {
      realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(1, id));
    }
    const fee = realRewards.sub(rewards);
    expect(rewards).eq(excludeFee(realRewards));

    const nftRewards = await calculateNftRewards(rewards, contracts.baycStrategy);

    await expect(contracts.bendStakeManager.claimBayc(baycTokenIds)).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address, contracts.bendStakeManager.address],
      [rewards.sub(nftRewards), nftRewards, fee]
    );

    for (const id of baycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(1, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(1)).eq(0);
  });

  const calculateNftRewards = async (rewards: BigNumber, strategy: IRewardsStrategy) => {
    return rewards.mul(await strategy.getNftRewardsShare()).div(10000);
  };

  it("unstakeBayc: unstake fully", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(1);
    const realRewards = await contracts.bendStakeManager.pendingRewardsIncludeFee(1);
    const fee = realRewards.sub(rewards);

    const baycPoolRewards = await calculateNftRewards(rewards, contracts.baycStrategy);

    const unstakeAmount = await contracts.bendStakeManager.stakedApeCoin(1);

    await expect(contracts.bendStakeManager.unstakeBayc(baycTokenIds)).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address, contracts.bendStakeManager.address],
      [unstakeAmount.add(rewards.sub(baycPoolRewards)), baycPoolRewards, fee]
    );

    for (const id of baycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(1, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(1)).eq(0);
    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(0);
  });

  it("unstakeBayc: unstake partially", async () => {
    await advanceHours(10);
    let realRewards = constants.Zero;
    let unstakeAmount = constants.Zero;
    let stakeAmount = constants.Zero;
    let pendingRewards = constants.Zero;
    const unstakeBaycTokenId = [];
    for (const [i, id] of baycTokenIds.entries()) {
      if (i % 2 === 1) {
        unstakeBaycTokenId.push(id);
        realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(1, id));
        unstakeAmount = unstakeAmount.add((await contracts.apeStaking.nftPosition(1, id)).stakedAmount);
      } else {
        pendingRewards = pendingRewards.add(await contracts.apeStaking.pendingRewards(1, id));
        stakeAmount = stakeAmount.add((await contracts.apeStaking.nftPosition(1, id)).stakedAmount);
      }
    }
    const rewards = excludeFee(realRewards);
    const fee = realRewards.sub(rewards);

    const baycPoolRewards = await calculateNftRewards(rewards, contracts.baycStrategy);
    await expect(contracts.bendStakeManager.unstakeBayc(unstakeBaycTokenId)).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address, contracts.bendStakeManager.address],
      [unstakeAmount.add(rewards.sub(baycPoolRewards)), baycPoolRewards, fee]
    );

    for (const id of unstakeBaycTokenId) {
      expect(await contracts.apeStaking.pendingRewards(1, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(1)).eq(excludeFee(pendingRewards));
    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(stakeAmount);
  });

  it("stakeMayc", async () => {
    await advanceHours(10);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(2);
    const requiredAmount = makeBN18(2042 * maycTokenIds.length);
    const preStakedTotal = await contracts.apeStaking.stakedTotal([], maycTokenIds, []);
    await expectStake(() => {
      return contracts.bendStakeManager.stakeMayc(maycTokenIds);
    }, requiredAmount);

    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(stakedAmount.add(requiredAmount));

    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(
      (await contracts.apeStaking.stakedTotal([], maycTokenIds, [])).sub(preStakedTotal)
    );

    lastRevert = "stakeMayc";
    await snapshots.capture(lastRevert);
  });

  it("claimMayc", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(2);
    let realRewards = constants.Zero;

    for (const id of maycTokenIds) {
      realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(2, id));
    }
    const fee = realRewards.sub(rewards);

    expect(rewards).eq(excludeFee(realRewards));

    const nftRewards = await calculateNftRewards(rewards, contracts.maycStrategy);

    await expect(contracts.bendStakeManager.claimMayc(maycTokenIds)).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address, contracts.bendStakeManager.address],
      [rewards.sub(nftRewards), nftRewards, fee]
    );

    for (const id of maycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(2, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(2)).eq(0);
  });

  it("unstakeMayc: unstake fully", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(2);
    const realRewards = await contracts.bendStakeManager.pendingRewardsIncludeFee(2);
    const fee = realRewards.sub(rewards);
    const maycPoolRewards = await calculateNftRewards(rewards, contracts.maycStrategy);
    const unstakeAmount = await contracts.bendStakeManager.stakedApeCoin(2);

    await expect(contracts.bendStakeManager.unstakeMayc(maycTokenIds)).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address, contracts.bendStakeManager.address],
      [unstakeAmount.add(rewards.sub(maycPoolRewards)), maycPoolRewards, fee]
    );

    for (const id of maycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(2, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(2)).eq(0);
    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(0);
  });

  it("unstakeMayc: unstake partially", async () => {
    await advanceHours(10);
    let realRewards = constants.Zero;
    let unstakeAmount = constants.Zero;
    let stakeAmount = constants.Zero;
    let pendingRewards = constants.Zero;
    const unstakeMaycTokenId = [];
    for (const [i, id] of maycTokenIds.entries()) {
      if (i % 2 === 1) {
        unstakeMaycTokenId.push(id);
        realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(2, id));
        unstakeAmount = unstakeAmount.add((await contracts.apeStaking.nftPosition(2, id)).stakedAmount);
      } else {
        pendingRewards = pendingRewards.add(await contracts.apeStaking.pendingRewards(2, id));
        stakeAmount = stakeAmount.add((await contracts.apeStaking.nftPosition(2, id)).stakedAmount);
      }
    }
    const rewards = excludeFee(realRewards);
    const fee = realRewards.sub(rewards);

    const maycPoolRewards = await calculateNftRewards(rewards, contracts.maycStrategy);
    await expect(contracts.bendStakeManager.unstakeMayc(unstakeMaycTokenId)).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address, contracts.bendStakeManager.address],
      [unstakeAmount.add(rewards.sub(maycPoolRewards)), maycPoolRewards, fee]
    );

    for (const id of unstakeMaycTokenId) {
      expect(await contracts.apeStaking.pendingRewards(2, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(2)).eq(excludeFee(pendingRewards));
    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(stakeAmount);
  });

  it("stakeBakc", async () => {
    await advanceHours(10);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(3);
    const requiredAmount = makeBN18(856 * bakcTokenIds.length);
    const preStakedTotal = await contracts.apeStaking.stakedTotal([], [], bakcTokenIds);

    await expectStake(() => {
      return contracts.bendStakeManager.stakeBakc(bakcTokenIds);
    }, requiredAmount);

    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(stakedAmount.add(requiredAmount));

    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(
      (await contracts.apeStaking.stakedTotal([], [], bakcTokenIds)).sub(preStakedTotal)
    );

    lastRevert = "stakeBakc";
    await snapshots.capture(lastRevert);
  });

  it("claimBakc", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(3);
    let realRewards = constants.Zero;

    for (const id of bakcTokenIds) {
      realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(3, id));
    }
    expect(rewards).eq(excludeFee(realRewards));
    const fee = realRewards.sub(rewards);

    const bakcPoolRewards = await calculateNftRewards(rewards, contracts.bakcStrategy);

    await expect(contracts.bendStakeManager.claimBakc(bakcTokenIds)).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address, contracts.bendStakeManager.address],
      [rewards.sub(bakcPoolRewards), bakcPoolRewards, fee]
    );

    for (const id of bakcTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(3, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(0);
  });

  it("unstakeBakc: unstake fully", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(3);
    const realRewards = await contracts.bendStakeManager.pendingRewardsIncludeFee(3);
    const fee = realRewards.sub(rewards);
    const bakcPoolRewards = await calculateNftRewards(rewards, contracts.bakcStrategy);
    const unstakeAmount = await contracts.bendStakeManager.stakedApeCoin(3);

    await expect(contracts.bendStakeManager.unstakeBakc(bakcTokenIds)).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address, contracts.bendStakeManager.address],
      [unstakeAmount.add(rewards.sub(bakcPoolRewards)), bakcPoolRewards, fee]
    );

    for (const id of bakcTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(3, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(0);
    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(0);
  });

  it("unstakBakc: unstake partially", async () => {
    await advanceHours(10);
    let realRewards = constants.Zero;
    let unstakeAmount = constants.Zero;
    let stakeAmount = constants.Zero;
    let realPendingRewards = constants.Zero;
    const unstakeBakcTokenId = [];

    for (const [i, id] of bakcTokenIds.entries()) {
      if (i % 2 === 1) {
        unstakeBakcTokenId.push(id);
        realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(3, id));
        unstakeAmount = unstakeAmount.add((await contracts.apeStaking.nftPosition(3, id)).stakedAmount);
      } else {
        realPendingRewards = realPendingRewards.add(await contracts.apeStaking.pendingRewards(3, id));
        stakeAmount = stakeAmount.add((await contracts.apeStaking.nftPosition(3, id)).stakedAmount);
      }
    }
    const rewards = excludeFee(realRewards);
    const fee = realRewards.sub(rewards);
    const bakcPoolRewards = await calculateNftRewards(rewards, contracts.bakcStrategy);

    await expect(contracts.bendStakeManager.unstakeBakc(unstakeBakcTokenId)).changeTokenBalances(
      contracts.wrapApeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address, contracts.bendStakeManager.address],
      [unstakeAmount.add(rewards.sub(bakcPoolRewards)), bakcPoolRewards, fee]
    );

    for (const id of unstakeBakcTokenId) {
      expect(await contracts.apeStaking.pendingRewards(3, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(excludeFee(realPendingRewards));
    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(stakeAmount);
  });

  it("totalStakedApeCoin", async () => {
    expect(await contracts.bendStakeManager.totalStakedApeCoin()).eq(
      (await contracts.bendStakeManager.stakedApeCoin(0))
        .add(await contracts.bendStakeManager.stakedApeCoin(1))
        .add(await contracts.bendStakeManager.stakedApeCoin(2))
        .add(await contracts.bendStakeManager.stakedApeCoin(3))
    );

    await contracts.bendStakeManager.unstakeBayc(baycTokenIds);
    expect(await contracts.bendStakeManager.totalStakedApeCoin()).eq(
      (await contracts.bendStakeManager.stakedApeCoin(0))
        .add(await contracts.bendStakeManager.stakedApeCoin(2))
        .add(await contracts.bendStakeManager.stakedApeCoin(3))
    );

    await contracts.bendStakeManager.unstakeMayc(maycTokenIds);
    expect(await contracts.bendStakeManager.totalStakedApeCoin()).eq(
      (await contracts.bendStakeManager.stakedApeCoin(0)).add(await contracts.bendStakeManager.stakedApeCoin(3))
    );

    await contracts.bendStakeManager.unstakeBakc(bakcTokenIds);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(0);
    expect(await contracts.bendStakeManager.totalStakedApeCoin()).eq(stakedAmount);
  });

  it("withdrawApeCoin: withdraw all of ape coin", async () => {
    await advanceHours(10);

    const withdrawAmount = (await contracts.bendStakeManager.totalStakedApeCoin()).add(
      await contracts.bendStakeManager.totalPendingRewards()
    );

    console.log("test:withdrawApeCoin:", withdrawAmount);

    const coinPoolSigner = await ethers.getSigner(contracts.bendCoinPool.address);
    const preBalance = await contracts.wrapApeCoin.balanceOf(contracts.bendCoinPool.address);
    const preNftPoolBalance = await contracts.wrapApeCoin.balanceOf(contracts.bendNftPool.address);

    await contracts.bendStakeManager.connect(coinPoolSigner).withdrawApeCoin(withdrawAmount);

    const coinPoolReceived = (await contracts.wrapApeCoin.balanceOf(contracts.bendCoinPool.address)).sub(preBalance);
    const nftPoolReceived = (await contracts.wrapApeCoin.balanceOf(contracts.bendNftPool.address)).sub(
      preNftPoolBalance
    );
    expect(coinPoolReceived.add(nftPoolReceived)).closeTo(withdrawAmount, 5);
  });

  it("Revert Snapshot to stakeBayc", async () => {
    lastRevert = "stakeBayc";
  });

  it("asyncInit", async () => {
    await contracts.mockBeacon.setFees(parseEther("0.399572542890580499"), 0);
    await contracts.bayc.setLocked(baycTokenIds[0], true);

    lastRevert = "asyncInit";
    await snapshots.capture(lastRevert);
  });

  it("Async: claimBayc", async () => {
    await advanceHours(10);

    const rawRewards = await contracts.apeStaking.pendingRewards(1, baycTokenIds[0]);
    const claimFee = await contracts.apeStaking.quoteRequest(1, [baycTokenIds[0]]);
    const realRewards = rawRewards.sub(claimFee);

    // request claim
    console.log("claimBayc:", realRewards);

    const vaultBalanceBeforeClaim = await nftVaultSigner.getBalance();
    const nftBalanceBeforeClaim = await contracts.wrapApeCoin.balanceOf(contracts.bendNftPool.address);
    const stakeBalanceBeforeClaim = await contracts.wrapApeCoin.balanceOf(contracts.bendStakeManager.address);

    const guidClaim = await contracts.bayc.getNextGUID();
    await contracts.bendStakeManager.claimBayc([baycTokenIds[0]]);

    const vaultBalanceAfterClaim = await nftVaultSigner.getBalance();
    const nftBalanceAfterClaim = await contracts.wrapApeCoin.balanceOf(contracts.bendNftPool.address);
    const stakeBalanceAfterClaim = await contracts.wrapApeCoin.balanceOf(contracts.bendStakeManager.address);

    expect(vaultBalanceAfterClaim).lt(vaultBalanceBeforeClaim); // some gas cost
    expect(nftBalanceBeforeClaim).eq(nftBalanceAfterClaim);
    expect(stakeBalanceBeforeClaim).eq(stakeBalanceAfterClaim);

    // execute callback
    console.log("executeCallback:");

    const vaultBalanceBeforeCallback = await nftVaultSigner.getBalance();

    await contracts.bayc.executeCallback(contracts.apeStaking.address, guidClaim);

    const vaultBalanceAfterCallback = await nftVaultSigner.getBalance();

    expect(vaultBalanceAfterCallback).eq(vaultBalanceBeforeCallback.add(rawRewards));

    // compound rewards

    const rewardsNoFee = excludeFee(realRewards);
    const nftRewards = await calculateNftRewards(rewardsNoFee, contracts.baycStrategy);
    const coinRewards = rewardsNoFee.sub(nftRewards);

    console.log("distributePendingFunds:", realRewards, rewardsNoFee, nftRewards);

    const vaultBalanceBeforeCompound = await nftVaultSigner.getBalance();
    const nftBalanceBeforeCompound = await contracts.wrapApeCoin.balanceOf(contracts.bendNftPool.address);
    const coinBalanceBeforeCompound = await contracts.wrapApeCoin.balanceOf(contracts.bendCoinPool.address);

    await contracts.bendStakeManager.distributePendingFunds();

    const vaultBalanceAfterCompound = await nftVaultSigner.getBalance();
    const nftBalanceAfterCompound = await contracts.wrapApeCoin.balanceOf(contracts.bendNftPool.address);
    const coinBalanceAfterCompound = await contracts.wrapApeCoin.balanceOf(contracts.bendCoinPool.address);

    expect(vaultBalanceAfterCompound).eq(vaultBalanceBeforeCompound.sub(realRewards)); // some gas cost
    expect(nftBalanceAfterCompound).eq(nftBalanceBeforeCompound.add(nftRewards));
    expect(coinBalanceAfterCompound).eq(coinBalanceBeforeCompound.add(coinRewards));
  });

  it("Async: unstakeBayc", async () => {
    await advanceHours(10);

    const principal = (await contracts.apeStaking.nftPosition(1, baycTokenIds[0])).stakedAmount;
    const rawRewards = await contracts.apeStaking.pendingRewards(1, baycTokenIds[0]);
    const claimFee = await contracts.apeStaking.quoteRequest(1, [baycTokenIds[0]]);
    const realRewards = rawRewards.sub(claimFee);

    // request claim
    console.log("unstakeBayc:", realRewards);

    const vaultBalanceBeforeClaim = await nftVaultSigner.getBalance();
    const nftBalanceBeforeClaim = await contracts.wrapApeCoin.balanceOf(contracts.bendNftPool.address);
    const stakeBalanceBeforeClaim = await contracts.wrapApeCoin.balanceOf(contracts.bendStakeManager.address);

    const guidClaim = await contracts.bayc.getNextGUID();
    await contracts.bendStakeManager.unstakeBayc([baycTokenIds[0]]);

    const vaultBalanceAfterClaim = await nftVaultSigner.getBalance();
    const nftBalanceAfterClaim = await contracts.wrapApeCoin.balanceOf(contracts.bendNftPool.address);
    const stakeBalanceAfterClaim = await contracts.wrapApeCoin.balanceOf(contracts.bendStakeManager.address);

    expect(vaultBalanceAfterClaim).lt(vaultBalanceBeforeClaim); // some gas cost
    expect(nftBalanceBeforeClaim).eq(nftBalanceAfterClaim);
    expect(stakeBalanceBeforeClaim).eq(stakeBalanceAfterClaim);

    // execute callback
    console.log("executeCallback:");

    const vaultBalanceBeforeCallback = await nftVaultSigner.getBalance();

    await contracts.bayc.executeCallback(contracts.apeStaking.address, guidClaim);

    const vaultBalanceAfterCallback = await nftVaultSigner.getBalance();

    expect(vaultBalanceAfterCallback).eq(vaultBalanceBeforeCallback.add(principal).add(rawRewards));

    // compound rewards

    const rewardsNoFee = excludeFee(realRewards);
    const nftRewards = await calculateNftRewards(rewardsNoFee, contracts.baycStrategy);
    const coinRewards = rewardsNoFee.sub(nftRewards);

    console.log("distributePendingFunds:", realRewards, rewardsNoFee, nftRewards);

    const vaultBalanceBeforeCompound = await nftVaultSigner.getBalance();
    const nftBalanceBeforeCompound = await contracts.wrapApeCoin.balanceOf(contracts.bendNftPool.address);
    const coinBalanceBeforeCompound = await contracts.wrapApeCoin.balanceOf(contracts.bendCoinPool.address);

    await contracts.bendStakeManager.distributePendingFunds();

    const vaultBalanceAfterCompound = await nftVaultSigner.getBalance();
    const nftBalanceAfterCompound = await contracts.wrapApeCoin.balanceOf(contracts.bendNftPool.address);
    const coinBalanceAfterCompound = await contracts.wrapApeCoin.balanceOf(contracts.bendCoinPool.address);

    expect(vaultBalanceAfterCompound).eq(vaultBalanceBeforeCompound.sub(principal).sub(realRewards)); // some gas cost
    expect(nftBalanceAfterCompound).eq(nftBalanceBeforeCompound.add(nftRewards));
    expect(coinBalanceAfterCompound).eq(coinBalanceBeforeCompound.add(principal).add(coinRewards));
  });
});
