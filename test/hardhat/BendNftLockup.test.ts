import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./setup";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { advanceHours, getContract, makeBN18, mintNft, shuffledSubarray } from "./utils";
import { BigNumber, constants } from "ethers";
import { arrayify } from "ethers/lib/utils";

makeSuite("BendNftLockup", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let owner: SignerWithAddress;
  let bot: SignerWithAddress;
  let baycTokenIds: number[];
  let maycTokenIds: number[];
  let bakcTokenIds: number[];
  let lastRevert: string;
  let zeroBytes32 = arrayify("0x0000000000000000000000000000000000000000000000000000000000000000");

  before(async () => {
    owner = env.accounts[1];
    bot = env.accounts[3];

    baycTokenIds = [0, 1, 2, 3, 4, 5];
    await mintNft(owner, contracts.bayc, baycTokenIds);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.bendNftLockup.address, true);

    maycTokenIds = [6, 7, 8, 9, 10];
    await mintNft(owner, contracts.mayc, maycTokenIds);
    await contracts.mayc.connect(owner).setApprovalForAll(contracts.bendNftLockup.address, true);

    bakcTokenIds = [10, 11, 12, 13, 14];
    await mintNft(owner, contracts.bakc, bakcTokenIds);
    await contracts.bakc.connect(owner).setApprovalForAll(contracts.bendNftLockup.address, true);

    await contracts.bendNftLockup.setBotAdmin(bot.address);

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });

  it("onlyOwner: reverts", async () => {
    await expect(contracts.bendNftLockup.connect(owner).setBotAdmin(constants.AddressZero)).revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(contracts.bendNftLockup.connect(owner).setDelegationRegistryV2(constants.AddressZero)).revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(contracts.bendNftLockup.connect(owner).setNftShadowRights(zeroBytes32)).revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(contracts.bendNftLockup.connect(owner).setMaxOpInterval(100)).revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(contracts.bendNftLockup.connect(owner).setPause(true)).revertedWith(
      "Ownable: caller is not the owner"
    );
  });

  it("onlyApe: reverts", async () => {
    await expect(contracts.bendNftLockup.deposit([contracts.wrapApeCoin.address], [baycTokenIds])).revertedWith(
      "BendNftLockup: not ape"
    );

    await expect(contracts.bendNftLockup.withdraw([contracts.wrapApeCoin.address], [baycTokenIds])).revertedWith(
      "BendNftLockup: not ape"
    );
  });

  it("onlyBot: reverts", async () => {
    await expect(
      contracts.bendNftLockup.finalize([contracts.bayc.address], [baycTokenIds], owner.address)
    ).revertedWith("BendNftLockup: caller not bot admin");
  });

  it("deposit: revert when paused", async () => {
    await contracts.bendNftLockup.setPause(true);
    await expect(contracts.bendNftLockup.connect(owner).deposit([contracts.bayc.address], [baycTokenIds])).revertedWith(
      "Pausable: paused"
    );
    await contracts.bendNftLockup.setPause(false);
  });

  it("deposit: bayc", async () => {
    await contracts.bendNftLockup.connect(owner).deposit([contracts.bayc.address], [baycTokenIds]);

    for (const id of baycTokenIds) {
      expect(await contracts.bayc.ownerOf(id)).eq(contracts.bendNftLockup.address);
    }

    lastRevert = "deposit:bayc";
    await snapshots.capture(lastRevert);
  });

  it("withdraw: revert when paused", async () => {
    await contracts.bendNftLockup.setPause(true);
    await expect(
      contracts.bendNftLockup.connect(owner).withdraw([contracts.bayc.address], [baycTokenIds])
    ).revertedWith("Pausable: paused");
    await contracts.bendNftLockup.setPause(false);
  });

  it("withdraw: bayc and revert", async () => {
    await expect(
      contracts.bendNftLockup.connect(owner).withdraw([contracts.bayc.address], [baycTokenIds])
    ).revertedWith("BendNftLockup: interval not enough");
  });

  it("withdraw: bayc", async () => {
    await advanceHours(12);

    await contracts.bendNftLockup.connect(owner).withdraw([contracts.bayc.address], [baycTokenIds]);

    for (const id of baycTokenIds) {
      expect(await contracts.bayc.ownerOf(id)).eq(contracts.bendNftLockup.address);
    }

    lastRevert = "withdraw:bayc";
    await snapshots.capture(lastRevert);
  });

  it("finalize: bayc", async () => {
    await contracts.bendNftLockup.connect(bot).finalize([contracts.bayc.address], [baycTokenIds], owner.address);

    for (const id of baycTokenIds) {
      expect(await contracts.bayc.ownerOf(id)).eq(owner.address);
    }

    lastRevert = "init";
  });

  it("deposit: bayc & mayc & bakc", async () => {
    await contracts.bendNftLockup
      .connect(owner)
      .deposit(
        [contracts.bayc.address, contracts.mayc.address, contracts.bakc.address],
        [baycTokenIds, maycTokenIds, bakcTokenIds]
      );

    for (const id of baycTokenIds) {
      expect(await contracts.bayc.ownerOf(id)).eq(contracts.bendNftLockup.address);
    }
    for (const id of maycTokenIds) {
      expect(await contracts.mayc.ownerOf(id)).eq(contracts.bendNftLockup.address);
    }
    for (const id of bakcTokenIds) {
      expect(await contracts.bakc.ownerOf(id)).eq(contracts.bendNftLockup.address);
    }

    lastRevert = "deposit:bayc:mayc:bakc";
    await snapshots.capture(lastRevert);
  });

  it("withdraw: bayc & mayc & bakc", async () => {
    await advanceHours(12);

    await contracts.bendNftLockup
      .connect(owner)
      .withdraw(
        [contracts.bayc.address, contracts.mayc.address, contracts.bakc.address],
        [baycTokenIds, maycTokenIds, bakcTokenIds]
      );

    for (const id of baycTokenIds) {
      expect(await contracts.bayc.ownerOf(id)).eq(contracts.bendNftLockup.address);
    }
    for (const id of maycTokenIds) {
      expect(await contracts.mayc.ownerOf(id)).eq(contracts.bendNftLockup.address);
    }
    for (const id of bakcTokenIds) {
      expect(await contracts.bakc.ownerOf(id)).eq(contracts.bendNftLockup.address);
    }

    lastRevert = "withdraw:bayc:mayc:bakc";
    await snapshots.capture(lastRevert);
  });

  it("finalize: bayc & mayc & bakc", async () => {
    await contracts.bendNftLockup
      .connect(bot)
      .finalize(
        [contracts.bayc.address, contracts.mayc.address, contracts.bakc.address],
        [baycTokenIds, maycTokenIds, bakcTokenIds],
        owner.address
      );

    for (const id of baycTokenIds) {
      expect(await contracts.bayc.ownerOf(id)).eq(owner.address);
    }

    lastRevert = "init";
  });
});
