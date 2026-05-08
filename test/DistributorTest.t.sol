// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "../contracts/TokenDistributor.sol";
import "../contracts/DistributorFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18); // Mint 1M tokens to deployer
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DistributorTest is Test {
    DistributorFactory public factory;
    MockERC20 public token;

    address public owner = address(0x1);
    address public operator = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);

    uint256 public constant TOTAL_AMOUNT = 1000 * 10 ** 18;
    uint256 public constant USER_AMOUNT = 100 * 10 ** 18;

    function setUp() public {
        // Deploy contracts
        factory = new DistributorFactory();
        token = new MockERC20("Test Token", "TEST");

        // Fund owner
        token.mint(owner, TOTAL_AMOUNT * 10);

        // Set up labels for better test output
        vm.label(owner, "Owner");
        vm.label(operator, "Operator");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
    }

    function _createDistributor() internal returns (address distributorAddress) {
        vm.startPrank(owner);
        token.approve(address(factory), TOTAL_AMOUNT);
        distributorAddress = factory.createDistributor(address(token), operator, TOTAL_AMOUNT);
        vm.stopPrank();
    }

    // Merkle tree generation helper
    struct MerkleUser {
        address account;
        uint256 amount;
    }

    function _generateMerkleTree(MerkleUser[] memory users) internal pure returns (bytes32 root) {
        require(users.length > 0, "No users provided");

        // Create leaves for all users
        bytes32[] memory leaves = new bytes32[](4); // Pad to power of 2
        for (uint i = 0; i < users.length && i < 4; i++) {
            leaves[i] = keccak256(abi.encodePacked(users[i].account, users[i].amount));
        }
        // Pad remaining leaves with zero
        for (uint i = users.length; i < 4; i++) {
            leaves[i] = bytes32(0);
        }

        // Build 2-level tree
        bytes32 hash01 = keccak256(abi.encodePacked(leaves[0], leaves[1]));
        bytes32 hash23 = keccak256(abi.encodePacked(leaves[2], leaves[3]));
        root = keccak256(abi.encodePacked(hash01, hash23));
    }

    function _generateMerkleProof(
        address targetAccount,
        uint256 targetAmount,
        MerkleUser[] memory allUsers
    ) internal pure returns (bytes32[] memory proof, bytes32 root) {
        // Create leaves for all users
        bytes32[] memory leaves = new bytes32[](allUsers.length);
        for (uint i = 0; i < allUsers.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(allUsers[i].account, allUsers[i].amount));
        }

        // Find target leaf index
        bytes32 targetLeaf = keccak256(abi.encodePacked(targetAccount, targetAmount));
        uint256 targetIndex = type(uint256).max;
        for (uint i = 0; i < leaves.length; i++) {
            if (leaves[i] == targetLeaf) {
                targetIndex = i;
                break;
            }
        }
        require(targetIndex != type(uint256).max, "Target not found in tree");

        // For 3 users, we need to pad to 4 leaves (next power of 2)
        bytes32[] memory paddedLeaves = new bytes32[](4);
        for (uint i = 0; i < allUsers.length; i++) {
            paddedLeaves[i] = leaves[i];
        }
        // Pad with zero hash
        for (uint i = allUsers.length; i < 4; i++) {
            paddedLeaves[i] = bytes32(0);
        }

        // Build simple 2-level tree for 4 leaves
        bytes32[] memory level1 = new bytes32[](2);
        level1[0] = keccak256(abi.encodePacked(paddedLeaves[0], paddedLeaves[1]));
        level1[1] = keccak256(abi.encodePacked(paddedLeaves[2], paddedLeaves[3]));

        root = keccak256(abi.encodePacked(level1[0], level1[1]));

        // Generate proof for target
        proof = new bytes32[](2);
        if (targetIndex < 2) {
            // Target is in left subtree
            if (targetIndex == 0) {
                proof[0] = paddedLeaves[1]; // Sibling
            } else {
                proof[0] = paddedLeaves[0]; // Sibling
            }
            proof[1] = level1[1]; // Right subtree root
        } else {
            // Target is in right subtree
            if (targetIndex == 2) {
                proof[0] = paddedLeaves[3]; // Sibling
            } else {
                proof[0] = paddedLeaves[2]; // Sibling
            }
            proof[1] = level1[0]; // Left subtree root
        }
    }

    // ================================
    // DistributorFactory Tests
    // ================================

    function test_CreateDistributor_Success() public {
        vm.startPrank(owner);

        // Pre-approve tokens
        token.approve(address(factory), TOTAL_AMOUNT);

        // Create distributor
        address distributorAddress = factory.createDistributor(address(token), operator, TOTAL_AMOUNT);

        // Verify distributor was created
        assertTrue(distributorAddress != address(0));
        assertTrue(factory.isDistributor(distributorAddress));

        // Verify token balance was transferred
        assertEq(token.balanceOf(distributorAddress), TOTAL_AMOUNT);
        assertEq(token.balanceOf(owner), TOTAL_AMOUNT * 10 - TOTAL_AMOUNT); // 10000 - 1000 = 9000

        vm.stopPrank();
    }

    function test_CreateDistributor_InvalidToken() public {
        vm.startPrank(owner);
        vm.expectRevert(DistributorFactory.InvalidToken.selector);
        factory.createDistributor(address(0), operator, TOTAL_AMOUNT);
        vm.stopPrank();
    }

    function test_CreateDistributor_InvalidOperator() public {
        vm.startPrank(owner);
        vm.expectRevert(DistributorFactory.InvalidOperator.selector);
        factory.createDistributor(address(token), address(0), TOTAL_AMOUNT);
        vm.stopPrank();
    }

    function test_CreateDistributor_ZeroAmount() public {
        vm.startPrank(owner);
        vm.expectRevert(DistributorFactory.InvalidTotalAmount.selector);
        factory.createDistributor(address(token), operator, 0);
        vm.stopPrank();
    }

    function test_CreateDistributor_InsufficientAllowance() public {
        vm.startPrank(owner);
        vm.expectRevert("ERC20: insufficient allowance");
        factory.createDistributor(address(token), operator, TOTAL_AMOUNT);
        vm.stopPrank();
    }

    // ================================
    // Distributor Contract Tests
    // ================================

    function test_Distributor_Constructor() public {
        vm.startPrank(owner);
        token.approve(address(factory), TOTAL_AMOUNT);

        address distributorAddress = factory.createDistributor(address(token), operator, TOTAL_AMOUNT);
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        // Verify constructor parameters
        assertEq(distributor.owner(), owner);
        assertEq(distributor.operator(), operator);
        assertEq(distributor.token(), address(token));
        // Check Balance of distributor
        assertEq(token.balanceOf(distributorAddress), TOTAL_AMOUNT);
        vm.stopPrank();
    }

    function test_SetStartTime_Success() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 futureTime = block.timestamp + 1 days;

        vm.prank(operator);
        distributor.setTime(futureTime, 14 days);

        assertEq(distributor.startTime(), futureTime);
        assertEq(distributor.endTime(), futureTime + 14 days);
    }

    function test_SetStartTime_OnlyOperator() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        vm.prank(user1);
        vm.expectRevert(TokenDistributor.OnlyOperator.selector);
        distributor.setTime(block.timestamp + 1 days, 14 days);
    }

    function test_SetStartTime_AlreadyStarted() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 futureTime = block.timestamp + 1 days;

        // Set initial time
        vm.prank(operator);
        distributor.setTime(futureTime, 14 days);

        // Fast forward to start time (distribution starts)
        vm.warp(futureTime);

        // Try to set time again after distribution started
        vm.prank(operator);
        vm.expectRevert(TokenDistributor.AlreadyStarted.selector);
        distributor.setTime(futureTime + 1 days, 14 days);
    }

    function test_SetStartTime_PastTime() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        vm.prank(operator);
        vm.expectRevert(TokenDistributor.InvalidTime.selector);
        distributor.setTime(block.timestamp - 1, 14 days);
    }

    function test_SetStartTime_ExceedsMaxTimeLimit() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        // Try to set time beyond 90 days limit
        uint256 invalidFutureTime = block.timestamp + 91 days;

        vm.prank(operator);
        vm.expectRevert(TokenDistributor.InvalidTime.selector);
        distributor.setTime(invalidFutureTime, 14 days);
    }

    function test_SetStartTime_WithinMaxTimeLimit() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        // Set time exactly at 90 days limit (should succeed)
        uint256 validFutureTime = block.timestamp + 90 days;

        vm.prank(operator);
        distributor.setTime(validFutureTime, 14 days);

        assertEq(distributor.startTime(), validFutureTime);
        assertEq(distributor.endTime(), validFutureTime + 14 days);
    }

    function test_SetStartTime_CanSetMultipleTimes() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 firstTime = block.timestamp + 1 days;
        uint256 secondTime = block.timestamp + 2 days;
        uint256 thirdTime = block.timestamp + 3 days;

        // First setting
        vm.prank(operator);
        distributor.setTime(firstTime, 14 days);
        assertEq(distributor.startTime(), firstTime);
        assertEq(distributor.endTime(), firstTime + 14 days);

        // Second setting (should overwrite)
        vm.prank(operator);
        distributor.setTime(secondTime, 14 days);
        assertEq(distributor.startTime(), secondTime);
        assertEq(distributor.endTime(), secondTime + 14 days);

        // Third setting (should overwrite again)
        vm.prank(operator);
        distributor.setTime(thirdTime, 14 days);
        assertEq(distributor.startTime(), thirdTime);
        assertEq(distributor.endTime(), thirdTime + 14 days);
    }

    function test_SetMerkleRoot_Success() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        bytes32 newRoot = keccak256("test");

        vm.prank(operator);
        distributor.setMerkleRoot(newRoot);

        assertEq(distributor.merkleRoot(), newRoot);
    }

    function test_SetMerkleRoot_OnlyOperator() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        bytes32 newRoot = keccak256("test");

        vm.prank(user1);
        vm.expectRevert(TokenDistributor.OnlyOperator.selector);
        distributor.setMerkleRoot(newRoot);
    }

    function test_SetMerkleRoot_ZeroRoot() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        vm.prank(operator);
        vm.expectRevert(TokenDistributor.InvalidRoot.selector);
        distributor.setMerkleRoot(bytes32(0));
    }

    function test_SetMerkleRoot_Update() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        bytes32 root1 = keccak256("test1");
        bytes32 root2 = keccak256("test2");

        vm.prank(operator);
        distributor.setMerkleRoot(root1);
        assertEq(distributor.merkleRoot(), root1);

        vm.prank(operator);
        distributor.setMerkleRoot(root2);
        assertEq(distributor.merkleRoot(), root2);
    }

    function test_Claim_Success() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        // Setup
        uint256 startTime = block.timestamp + 1 hours;
        bytes32 merkleRoot = keccak256(abi.encodePacked(user1, USER_AMOUNT));

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot);

        // Fast forward to claim period
        vm.warp(startTime + 1 hours);

        // Claim
        bytes32[] memory proof = new bytes32[](0);
        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);

        assertEq(token.balanceOf(user1), balanceBefore + USER_AMOUNT);
        assertEq(distributor.claimedAmounts(user1), USER_AMOUNT);
    }

    function test_Claim_StartTimeNotSet() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(TokenDistributor.StartTimeNotSet.selector);
        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);
    }

    function test_Claim_TooEarly() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(TokenDistributor.TooEarly.selector);
        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);
    }

    function test_Claim_TooLate() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        // Fast forward past end time
        vm.warp(startTime + 15 days);

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(TokenDistributor.TooLate.selector);
        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);
    }

    function test_Claim_NoMerkleRoot() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        vm.warp(startTime + 1 hours);

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(TokenDistributor.NoRoot.selector);
        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);
    }

    function test_Claim_InvalidAmount() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 startTime = block.timestamp + 1 hours;
        bytes32 merkleRoot = keccak256("test");

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot);

        vm.warp(startTime + 1 hours);

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(TokenDistributor.InvalidAmount.selector);
        vm.prank(user1);
        distributor.claim(0, proof);
    }

    function test_Claim_InvalidProof() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 startTime = block.timestamp + 1 hours;
        bytes32 merkleRoot = keccak256("different");

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot);

        vm.warp(startTime + 1 hours);

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(TokenDistributor.InvalidProof.selector);
        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);
    }

    function test_Claim_AlreadyClaimed() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 startTime = block.timestamp + 1 hours;
        bytes32 merkleRoot = keccak256(abi.encodePacked(user1, USER_AMOUNT));

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot);

        vm.warp(startTime + 1 hours);

        bytes32[] memory proof = new bytes32[](0);

        // First claim
        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);

        // Second claim should fail
        vm.expectRevert(TokenDistributor.InvalidAmount.selector);
        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);
    }

    function test_Claim_PartialClaim() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 startTime = block.timestamp + 1 hours;
        uint256 firstAmount = 100 * 10 ** 18;
        uint256 maxAmount = 200 * 10 ** 18;

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        vm.warp(startTime + 1 hours);

        bytes32[] memory proof = new bytes32[](0);

        // First partial claim - claim 100 tokens
        bytes32 merkleRoot1 = keccak256(abi.encodePacked(user1, firstAmount));
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot1);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        distributor.claim(firstAmount, proof);

        assertEq(token.balanceOf(user1), balanceBefore + firstAmount);
        assertEq(distributor.claimedAmounts(user1), firstAmount);

        // Second partial claim - increase max claimable to 200, user gets additional 100
        bytes32 merkleRoot2 = keccak256(abi.encodePacked(user1, maxAmount));
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot2);

        uint256 balanceBeforeSecond = token.balanceOf(user1);
        vm.prank(user1);
        distributor.claim(maxAmount, proof);

        assertEq(token.balanceOf(user1), balanceBeforeSecond + (maxAmount - firstAmount));
        assertEq(distributor.claimedAmounts(user1), maxAmount);
    }

    function test_Withdraw_Success() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        // Fast forward past end time
        vm.warp(startTime + 15 days);

        uint256 balanceBefore = token.balanceOf(owner);
        uint256 contractBalance = token.balanceOf(distributorAddress);

        vm.prank(owner);
        distributor.withdraw();

        assertEq(token.balanceOf(owner), balanceBefore + contractBalance);
        assertEq(token.balanceOf(distributorAddress), 0);
    }

    function test_Withdraw_OnlyOwner() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        vm.warp(startTime + 15 days);

        vm.prank(user1);
        vm.expectRevert(TokenDistributor.OnlyOwner.selector);
        distributor.withdraw();
    }

    function test_Withdraw_BeforeStartTime_Success() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        // When startTime is 0, endTime is also 0, so block.timestamp > 0 is always true
        uint256 balanceBefore = token.balanceOf(owner);
        uint256 contractBalance = token.balanceOf(distributorAddress);

        vm.prank(owner);
        distributor.withdraw();

        assertEq(token.balanceOf(owner), balanceBefore + contractBalance);
        assertEq(token.balanceOf(distributorAddress), 0);
    }

    function test_Withdraw_DuringAirdropPeriod_Fails() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        vm.warp(startTime + 1 days); // During airdrop period (before end time)

        vm.prank(owner);
        vm.expectRevert(TokenDistributor.InvalidTime.selector);
        distributor.withdraw();
    }

    // ================================
    // Integration Tests
    // ================================

    function test_FullWorkflow() public {
        // Create distributor
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        // Set up campaign
        uint256 startTime = block.timestamp + 1 hours;
        bytes32 merkleRoot = keccak256(abi.encodePacked(user1, USER_AMOUNT));

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot);

        // Fast forward to active period
        vm.warp(startTime + 1 hours);

        // User claims
        bytes32[] memory proof = new bytes32[](0);
        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);

        assertEq(token.balanceOf(user1), balanceBefore + USER_AMOUNT);

        // Fast forward past end time
        vm.warp(startTime + 15 days);

        // Owner withdraws remaining
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 remainingBalance = token.balanceOf(distributorAddress);

        vm.prank(owner);
        distributor.withdraw();

        assertEq(token.balanceOf(owner), ownerBalanceBefore + remainingBalance);
        assertEq(token.balanceOf(distributorAddress), 0);
    }

    function test_MultipleUsersWorkflow() public {
        // Create distributor with larger amount
        uint256 largeAmount = 10000 * 10 ** 18;
        vm.startPrank(owner);
        token.approve(address(factory), largeAmount);
        address distributorAddress = factory.createDistributor(address(token), operator, largeAmount);
        vm.stopPrank();

        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        // Set up campaign
        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        // Set up different amounts for different users
        uint256 user1Amount = 1000 * 10 ** 18;
        uint256 user2Amount = 2000 * 10 ** 18;
        uint256 user3Amount = 3000 * 10 ** 18;

        bytes32 merkleRoot1 = keccak256(abi.encodePacked(user1, user1Amount));
        bytes32 merkleRoot2 = keccak256(abi.encodePacked(user2, user2Amount));
        bytes32 merkleRoot3 = keccak256(abi.encodePacked(user3, user3Amount));

        vm.warp(startTime + 1 hours);

        // User1 claims
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot1);

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(user1);
        distributor.claim(user1Amount, proof);

        assertEq(token.balanceOf(user1), user1Amount);

        // User2 claims
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot2);

        vm.prank(user2);
        distributor.claim(user2Amount, proof);

        assertEq(token.balanceOf(user2), user2Amount);

        // User3 claims
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot3);

        vm.prank(user3);
        distributor.claim(user3Amount, proof);

        assertEq(token.balanceOf(user3), user3Amount);

        // Verify total claimed
        assertEq(distributor.claimedAmounts(user1), user1Amount);
        assertEq(distributor.claimedAmounts(user2), user2Amount);
        assertEq(distributor.claimedAmounts(user3), user3Amount);
    }

    function test_SetTime_ZeroDuration_Fails() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 validStartTime = block.timestamp + 1 hours;
        
        // Zero duration should fail
        vm.prank(operator);
        vm.expectRevert(TokenDistributor.InvalidDuration.selector);
        distributor.setTime(validStartTime, 0);
    }
}
