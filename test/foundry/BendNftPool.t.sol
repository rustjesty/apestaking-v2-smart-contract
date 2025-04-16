pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendNftPoolTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function testSingleUserDepositWithdrawBAYCNoRewards() public {
        address testUser = testUsers[0];
        uint256[] memory testBaycTokenIds = new uint256[](1);

        vm.startPrank(testUser);

        mockBAYC.setApprovalForAll(address(nftPool), true);

        testBaycTokenIds[0] = 100;
        mockBAYC.mint(testBaycTokenIds[0]);
        address[] memory nfts = new address[](1);
        uint256[][] memory tokenIds = new uint256[][](1);

        mockBAYC.safeTransferFrom(testUser, address(nftVault), testBaycTokenIds[0]);

        vm.stopPrank();

        nfts[0] = address(mockBAYC);
        tokenIds[0] = testBaycTokenIds;
        vm.prank(address(stakeManager));
        nftPool.deposit(nfts, tokenIds, address(testUser));

        // make some rewards
        advanceTimeAndBlock(12 hours, 100);

        vm.prank(address(testUser));
        nftPool.claim(nfts, tokenIds);

        vm.prank(address(stakeManager));
        nftPool.withdraw(nfts, tokenIds, address(testUser));
    }

    function testSingleUserBatchDepositWithdrawBAYCNoRewards() public {
        address testUser = testUsers[0];
        uint256[] memory testBaycTokenIds = new uint256[](3);

        vm.startPrank(testUser);

        mockBAYC.setApprovalForAll(address(nftPool), true);

        testBaycTokenIds[0] = 100;
        mockBAYC.mint(testBaycTokenIds[0]);

        testBaycTokenIds[1] = 200;
        mockBAYC.mint(testBaycTokenIds[1]);

        testBaycTokenIds[2] = 300;
        mockBAYC.mint(testBaycTokenIds[2]);

        mockBAYC.safeTransferFrom(testUser, address(nftVault), testBaycTokenIds[0]);
        mockBAYC.safeTransferFrom(testUser, address(nftVault), testBaycTokenIds[1]);
        mockBAYC.safeTransferFrom(testUser, address(nftVault), testBaycTokenIds[2]);

        vm.stopPrank();

        address[] memory nfts = new address[](1);
        uint256[][] memory tokenIds = new uint256[][](1);

        nfts[0] = address(mockBAYC);
        tokenIds[0] = testBaycTokenIds;

        vm.prank(address(stakeManager));
        nftPool.deposit(nfts, tokenIds, address(testUser));

        // make some rewards
        advanceTimeAndBlock(12 hours, 100);

        vm.prank(address(testUser));
        nftPool.claim(nfts, tokenIds);

        vm.prank(address(stakeManager));
        nftPool.withdraw(nfts, tokenIds, address(testUser));
    }
}
