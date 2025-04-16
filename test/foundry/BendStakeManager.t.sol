pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendStakeManagerTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function test_compound_StakeApeCoin() public {
        address testUser = testUsers[0];
        uint256 depositCoinAmount = 1_000_000 * 1e18;

        // deposit some coins
        vm.startPrank(testUser);
        mockWAPE.deposit{value: depositCoinAmount}();
        mockWAPE.approve(address(coinPool), depositCoinAmount);
        coinPool.deposit(depositCoinAmount, testUser);
        vm.stopPrank();

        // stake all coins
        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs1;
        compoundArgs1.coinStakeThreshold = 0;
        stakeManager.compound(compoundArgs1);
        vm.stopPrank();

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs2;
        compoundArgs2.claimCoinPool = true;
        stakeManager.compound(compoundArgs2);
        vm.stopPrank();

        uint256 userAssetAmount = coinPool.assetBalanceOf(testUser);

        // withdraw all coins
        vm.startPrank(testUser);
        coinPool.withdraw(userAssetAmount, testUser, testUser);
        vm.stopPrank();

        uint256 userBalanceAfterWithdraw = mockWAPE.balanceOf(testUser);
        assertEq(userBalanceAfterWithdraw, userAssetAmount, "user balance not match after withdraw");
        // there's no apecoin pool staking & rewards now
        assertEq(userAssetAmount, depositCoinAmount, "user asset not match deposited amout");
    }

    function test_compound_StakeBAYC() public {
        address testUser = testUsers[0];
        uint256 depositCoinAmount = 1_000_000 * 1e18;
        uint256[] memory testBaycTokenIds = new uint256[](1);

        // deposit some coins
        vm.startPrank(testUser);
        mockWAPE.deposit{value: depositCoinAmount}();
        mockWAPE.approve(address(coinPool), depositCoinAmount);
        coinPool.deposit(depositCoinAmount, testUser);
        vm.stopPrank();

        // deposit some nfts
        vm.startPrank(testUser);
        mockBAYC.setApprovalForAll(address(nftPool), true);

        testBaycTokenIds[0] = 100;
        mockBAYC.mint(testBaycTokenIds[0]);

        address[] memory nfts = new address[](1);
        uint256[][] memory tokenIds = new uint256[][](1);
        nfts[0] = address(mockBAYC);
        tokenIds[0] = testBaycTokenIds;

        mockBAYC.safeTransferFrom(testUser, address(nftVault), testBaycTokenIds[0]);

        vm.stopPrank();

        // deposit all nfts
        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs0;
        compoundArgs0.deposit.bayc.tokenIds = testBaycTokenIds;
        compoundArgs0.deposit.bayc.owner = testUser;
        stakeManager.compound(compoundArgs0);
        vm.stopPrank();

        // stake all nfts
        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs1;
        compoundArgs1.stake.bayc = testBaycTokenIds;
        stakeManager.compound(compoundArgs1);
        vm.stopPrank();

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs2;
        compoundArgs2.claimCoinPool = true;
        compoundArgs2.claim.bayc = testBaycTokenIds;
        stakeManager.compound(compoundArgs2);
        vm.stopPrank();

        vm.startPrank(testUser);
        uint256 rewardsAmount = nftPool.claimable(nfts, tokenIds);
        assertGt(rewardsAmount, 0, "rewards should greater than 0");
        vm.stopPrank();

        uint256 balanceBeforeUnstake = testUser.balance;

        // unstake all nfts
        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs3;
        compoundArgs3.unstake.bayc = testBaycTokenIds;
        stakeManager.compound(compoundArgs3);
        vm.stopPrank();

        // withdraw all nfts
        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs4;
        compoundArgs4.withdraw.bayc.tokenIds = testBaycTokenIds;
        compoundArgs4.withdraw.bayc.owner = testUser;
        stakeManager.compound(compoundArgs4);
        vm.stopPrank();

        uint256 balanceAmount = testUser.balance;
        assertEq(balanceAmount, balanceBeforeUnstake + rewardsAmount, "balance not match rewards");
    }

    function test_async_StakeBAYC() public {
        address testUser = testUsers[0];
        uint256 depositCoinAmount = 1_000_000 * 1e18;
        uint256[] memory testBaycTokenIds = new uint256[](1);

        // deposit some coins
        vm.startPrank(testUser);
        mockWAPE.deposit{value: depositCoinAmount}();
        mockWAPE.approve(address(coinPool), depositCoinAmount);
        coinPool.deposit(depositCoinAmount, testUser);
        vm.stopPrank();

        // deposit some nfts
        vm.startPrank(testUser);
        mockBAYC.setApprovalForAll(address(nftPool), true);

        testBaycTokenIds[0] = 100;
        mockBAYC.mint(testBaycTokenIds[0]);

        address[] memory nfts = new address[](1);
        uint256[][] memory tokenIds = new uint256[][](1);
        nfts[0] = address(mockBAYC);
        tokenIds[0] = testBaycTokenIds;

        mockBAYC.safeTransferFrom(testUser, address(nftVault), testBaycTokenIds[0]);

        vm.stopPrank();

        // configure apecoin staking to async mode
        mockBAYC.setLocked(testBaycTokenIds[0], true);
        mockBeacon.setFees(399572542890580499, 0);
        vm.deal(address(nftVault), 100 ether);

        // bot do some operations
        vm.startPrank(botAdmin);
        stakeManager.depositNft(nfts, tokenIds, testUser);

        stakeManager.stakeBayc(testBaycTokenIds);

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        bytes32 guidClaim = mockBAYC.getNextGUID();
        stakeManager.claimBayc(testBaycTokenIds);

        mockBAYC.executeCallback(address(mockApeStaking), guidClaim);

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        bytes32 guidUnstake = mockBAYC.getNextGUID();
        stakeManager.unstakeBayc(testBaycTokenIds);

        mockBAYC.executeCallback(address(mockApeStaking), guidUnstake);

        vm.stopPrank();
    }
}
