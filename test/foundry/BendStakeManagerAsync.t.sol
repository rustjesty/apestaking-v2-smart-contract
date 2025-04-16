pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendStakeManagerAsyncTest is SetupHelper {
    function setUp() public override {
        super.setUp();

        // configure apecoin staking to async mode
        mockBeacon.setFees(399572542890580499, 0);
        vm.deal(address(nftVault), 100 ether);
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

        mockBAYC.setLocked(testBaycTokenIds[0], true);

        // bot do some operations
        vm.startPrank(botAdmin);
        stakeManager.depositNft(nfts, tokenIds, testUser);

        stakeManager.stakeBayc(testBaycTokenIds);

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        bytes32 guidClaim = mockBAYC.getNextGUID();
        stakeManager.claimBayc(testBaycTokenIds);

        mockBAYC.executeCallback(address(mockApeStaking), guidClaim);

        stakeManager.distributePendingFunds();

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        bytes32 guidUnstake = mockBAYC.getNextGUID();
        stakeManager.unstakeBayc(testBaycTokenIds);

        mockBAYC.executeCallback(address(mockApeStaking), guidUnstake);

        stakeManager.distributePendingFunds();

        vm.stopPrank();
    }
}
