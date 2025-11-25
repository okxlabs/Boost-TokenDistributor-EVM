// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "../contracts/TokenDistributor.sol";
import "../contracts/DistributorFactory.sol";

/**
 * @title NativeTokenDistributorTest
 * @notice Test suite for native ETH token distribution functionality
 * @dev Tests the native token distribution using ETH_ADDRESS constant
 */
contract NativeTokenDistributorTest is Test {
    DistributorFactory public factory;
    
    address public owner = address(0x1);
    address public operator = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);
    
    uint256 public constant TOTAL_AMOUNT = 10 ether;
    uint256 public constant USER_AMOUNT = 1 ether;
    
    // ETH_ADDRESS constant used for native token distribution
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    function setUp() public {
        // Deploy factory
        factory = new DistributorFactory();
        
        // Fund owner with ETH
        vm.deal(owner, 100 ether);
        
        // Set up labels for better test output
        vm.label(owner, "Owner");
        vm.label(operator, "Operator");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(address(factory), "Factory");
    }
    
    function _createNativeDistributor() internal returns (address distributorAddress) {
        vm.startPrank(owner);
        distributorAddress = factory.createDistributor{value: TOTAL_AMOUNT}(
            ETH_ADDRESS, 
            operator, 
            TOTAL_AMOUNT
        );
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
    // Factory Tests for Native Token
    // ================================
    
    function test_CreateNativeDistributor_Success() public {
        uint256 ownerBalanceBefore = owner.balance;
        
        vm.startPrank(owner);
        address distributorAddress = factory.createDistributor{value: TOTAL_AMOUNT}(
            ETH_ADDRESS, 
            operator, 
            TOTAL_AMOUNT
        );
        vm.stopPrank();
        
        // Verify distributor was created
        assertTrue(distributorAddress != address(0));
        assertTrue(factory.isDistributor(distributorAddress));
        
        // Verify ETH balance was transferred
        assertEq(distributorAddress.balance, TOTAL_AMOUNT);
        assertEq(owner.balance, ownerBalanceBefore - TOTAL_AMOUNT);
    }
    
    function test_CreateNativeDistributor_InsufficientValue() public {
        vm.startPrank(owner);
        vm.expectRevert();
        factory.createDistributor{value: TOTAL_AMOUNT - 1}(
            ETH_ADDRESS, 
            operator, 
            TOTAL_AMOUNT
        );
        vm.stopPrank();
    }
    
    
    // ================================
    // Native Token Distribution Tests
    // ================================
    
    function test_NativeClaim_Success() public {
        address distributorAddress = _createNativeDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));
        
        // Setup
        uint256 startTime = block.timestamp + 1 hours;
        bytes32 merkleRoot = keccak256(abi.encodePacked(user1, USER_AMOUNT));
        
        vm.prank(operator);
        distributor.setTime(startTime);
        
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot);
        
        // Fast forward to claim period
        vm.warp(startTime + 1 hours);
        
        // Claim
        bytes32[] memory proof = new bytes32[](0);
        uint256 userBalanceBefore = user1.balance;
        
        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);
        
        assertEq(user1.balance, userBalanceBefore + USER_AMOUNT);
        assertEq(distributor.claimedAmounts(user1), USER_AMOUNT);
        assertEq(distributorAddress.balance, TOTAL_AMOUNT - USER_AMOUNT);
    }
    
    function test_NativeClaim_MultipleUsers() public {
        address distributorAddress = _createNativeDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));
        
        // Setup
        uint256 startTime = block.timestamp + 1 hours;
        
        vm.prank(operator);
        distributor.setTime(startTime);
        
        vm.warp(startTime + 1 hours);
        
        // User1 claims
        bytes32 merkleRoot1 = keccak256(abi.encodePacked(user1, USER_AMOUNT));
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot1);
        
        bytes32[] memory proof = new bytes32[](0);
        uint256 user1BalanceBefore = user1.balance;
        
        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);
        
        assertEq(user1.balance, user1BalanceBefore + USER_AMOUNT);
        
        // User2 claims
        bytes32 merkleRoot2 = keccak256(abi.encodePacked(user2, USER_AMOUNT * 2));
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot2);
        
        uint256 user2BalanceBefore = user2.balance;
        
        vm.prank(user2);
        distributor.claim(USER_AMOUNT * 2, proof);
        
        assertEq(user2.balance, user2BalanceBefore + USER_AMOUNT * 2);
        
        // Verify total claimed
        assertEq(distributor.claimedAmounts(user1), USER_AMOUNT);
        assertEq(distributor.claimedAmounts(user2), USER_AMOUNT * 2);
        assertEq(distributorAddress.balance, TOTAL_AMOUNT - USER_AMOUNT * 3);
    }
    
    function test_NativeClaim_PartialClaim() public {
        address distributorAddress = _createNativeDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));
        
        uint256 startTime = block.timestamp + 1 hours;
        uint256 firstAmount = 0.5 ether;
        uint256 maxAmount = 1 ether;
        
        vm.prank(operator);
        distributor.setTime(startTime);
        
        vm.warp(startTime + 1 hours);
        
        // First partial claim
        bytes32 merkleRoot1 = keccak256(abi.encodePacked(user1, firstAmount));
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot1);
        
        bytes32[] memory proof = new bytes32[](0);
        uint256 balanceBefore = user1.balance;
        
        vm.prank(user1);
        distributor.claim(firstAmount, proof);
        
        assertEq(user1.balance, balanceBefore + firstAmount);
        assertEq(distributor.claimedAmounts(user1), firstAmount);
        
        // Second partial claim - increase max claimable
        bytes32 merkleRoot2 = keccak256(abi.encodePacked(user1, maxAmount));
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot2);
        
        uint256 balanceBeforeSecond = user1.balance;
        vm.prank(user1);
        distributor.claim(maxAmount, proof);
        
        assertEq(user1.balance, balanceBeforeSecond + (maxAmount - firstAmount));
        assertEq(distributor.claimedAmounts(user1), maxAmount);
    }
    
    function test_NativeWithdraw_Success() public {
        address distributorAddress = _createNativeDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));
        
        uint256 startTime = block.timestamp + 1 hours;
        
        vm.prank(operator);
        distributor.setTime(startTime);
        
        // Fast forward past end time
        vm.warp(startTime + 15 days);
        
        uint256 ownerBalanceBefore = owner.balance;
        uint256 contractBalance = distributorAddress.balance;
        
        vm.prank(owner);
        distributor.withdraw();
        
        assertEq(owner.balance, ownerBalanceBefore + contractBalance);
        assertEq(distributorAddress.balance, 0);
    }
    
    function test_NativeWithdraw_BeforeStartTime_Success() public {
        address distributorAddress = _createNativeDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));
        
        // When startTime is 0, endTime is also 0, so block.timestamp > 0 is always true
        uint256 ownerBalanceBefore = owner.balance;
        uint256 contractBalance = distributorAddress.balance;
        
        vm.prank(owner);
        distributor.withdraw();
        
        assertEq(owner.balance, ownerBalanceBefore + contractBalance);
        assertEq(distributorAddress.balance, 0);
    }
    
    function test_NativeWithdraw_DuringAirdropPeriod_Fails() public {
        address distributorAddress = _createNativeDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));
        
        uint256 startTime = block.timestamp + 1 hours;
        
        vm.prank(operator);
        distributor.setTime(startTime);
        
        vm.warp(startTime + 1 days); // During airdrop period (before end time)
        
        vm.prank(owner);
        vm.expectRevert(TokenDistributor.InvalidTime.selector);
        distributor.withdraw();
    }
    
    function test_NativeClaim_TransferFailure() public {
        address distributorAddress = _createNativeDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));
        
        // Setup
        uint256 startTime = block.timestamp + 1 hours;
        
        vm.prank(operator);
        distributor.setTime(startTime);
        
        vm.warp(startTime + 1 hours);
        
        // Create a contract that rejects ETH transfers
        RejectingContract rejector = new RejectingContract();
        
        // Generate merkle root for the rejector contract
        bytes32 merkleRoot = keccak256(abi.encodePacked(address(rejector), USER_AMOUNT));
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot);
        
        // Try to claim to the rejecting contract
        bytes32[] memory proof = new bytes32[](0);
        
        vm.prank(address(rejector));
        vm.expectRevert(TokenDistributor.NativeSendFailed.selector);
        distributor.claim(USER_AMOUNT, proof);
    }    
    function test_NativeDistributor_ReceiveFunction_ValidToken() public {
        // Create native distributor (should accept ETH)
        address distributorAddress = _createNativeDistributor();
        // TokenDistributor distributor = TokenDistributor(payable(distributorAddress));
        
        uint256 initialBalance = distributorAddress.balance;
        uint256 additionalAmount = 1 ether;
        
        // Send ETH directly to the native token distributor
        vm.deal(address(this), additionalAmount);
        (bool success, ) = distributorAddress.call{value: additionalAmount}("");
        assertTrue(success, "Native distributor should accept ETH");
        
        assertEq(distributorAddress.balance, initialBalance + additionalAmount);
    }

    function test_ERC20Distributor_ReceiveFunction_RejectsETH() public {
        // Create ERC20 distributor (should reject ETH)
        MockERC20 token = new MockERC20("Test Token", "TEST");
        token.mint(owner, TOTAL_AMOUNT);
        
        vm.startPrank(owner);
        token.approve(address(factory), TOTAL_AMOUNT);
        address erc20DistributorAddress = factory.createDistributor(address(token), operator, TOTAL_AMOUNT);
        vm.stopPrank();
        
        // TokenDistributor erc20Distributor = TokenDistributor(payable(erc20DistributorAddress));
        
        uint256 initialBalance = erc20DistributorAddress.balance;
        uint256 additionalAmount = 1 ether;
        
        // Fund this test contract
        vm.deal(address(this), additionalAmount);
        
        // Try to send ETH to ERC20 distributor - should revert
        vm.expectRevert(TokenDistributor.NativeNotAccepted.selector);
        // @audit Low-level call used intentionally for testing
        erc20DistributorAddress.call{value: additionalAmount}("");
        
        // Verify balance didn't change
        assertEq(erc20DistributorAddress.balance, initialBalance);
    }
    function test_NativeDistributor_ReceiveFunction_MultipleTransfers() public {
        // Create native distributor
        address distributorAddress = _createNativeDistributor();
        // TokenDistributor distributor = TokenDistributor(payable(distributorAddress));
        
        uint256 initialBalance = distributorAddress.balance;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0.5 ether;
        amounts[1] = 1 ether;
        amounts[2] = 1.5 ether;
        
        uint256 totalAdditional = 0;
        
        // Fund this test contract
        vm.deal(address(this), 5 ether);
        
        // Send multiple ETH transfers
        for (uint i = 0; i < amounts.length; i++) {
            (bool success, ) = distributorAddress.call{value: amounts[i]}("");
            assertTrue(success, "Native distributor should accept all ETH transfers");
            totalAdditional += amounts[i];
        }
        
        assertEq(distributorAddress.balance, initialBalance + totalAdditional);
    }

    function test_ERC20Distributor_ReceiveFunction_WithDifferentTokens() public {
        // Test with different ERC20 tokens
        MockERC20 token1 = new MockERC20("Token1", "TK1");
        MockERC20 token2 = new MockERC20("Token2", "TK2");
        
        token1.mint(owner, TOTAL_AMOUNT);
        token2.mint(owner, TOTAL_AMOUNT);
        
        vm.startPrank(owner);
        token1.approve(address(factory), TOTAL_AMOUNT);
        token2.approve(address(factory), TOTAL_AMOUNT);
        
        address distributor1 = factory.createDistributor(address(token1), operator, TOTAL_AMOUNT);
        address distributor2 = factory.createDistributor(address(token2), operator, TOTAL_AMOUNT);
        vm.stopPrank();
        
        uint256 amount = 1 ether;
        vm.deal(address(this), amount * 2);
        
        // Both ERC20 distributors should reject ETH
        vm.expectRevert(TokenDistributor.NativeNotAccepted.selector);
        // @audit Low-level call used intentionally for testing
        distributor1.call{value: amount}("");
        
        vm.expectRevert(TokenDistributor.NativeNotAccepted.selector);
        // @audit Low-level call used intentionally for testing
        distributor2.call{value: amount}("");
    }

    function test_NativeDistributor_ReceiveFunction_EdgeCases() public {
        // Test with zero ETH transfer
        address distributorAddress = _createNativeDistributor();
        // TokenDistributor distributor = TokenDistributor(payable(distributorAddress));
        
        uint256 initialBalance = distributorAddress.balance;
        
        // Send zero ETH - should still work
        (bool success, ) = distributorAddress.call{value: 0}("");
        assertTrue(success, "Native distributor should accept zero ETH");
        assertEq(distributorAddress.balance, initialBalance);
        
        // Test with very small amount
        vm.deal(address(this), 1 wei);
        (bool success2, ) = distributorAddress.call{value: 1 wei}("");
        assertTrue(success2, "Native distributor should accept 1 wei");
        assertEq(distributorAddress.balance, initialBalance + 1 wei);
    }

    function test_CreateERC20Distributor_WithETH_ShouldRevert() public {
        // Create ERC20 token
        MockERC20 token = new MockERC20("Test Token", "TEST");
        token.mint(owner, TOTAL_AMOUNT);
        
        vm.startPrank(owner);
        token.approve(address(factory), TOTAL_AMOUNT);
        
        // Try to create ERC20 distributor with ETH - should revert
        vm.expectRevert(DistributorFactory.UnexpectedNative.selector);
        factory.createDistributor{value: 1 ether}(
            address(token), 
            operator, 
            TOTAL_AMOUNT
        );
        vm.stopPrank();
    }
    
    function test_CreateERC20Distributor_WithZeroETH_ShouldSucceed() public {
        // Create ERC20 token
        MockERC20 token = new MockERC20("Test Token", "TEST");
        token.mint(owner, TOTAL_AMOUNT);
        
        vm.startPrank(owner);
        token.approve(address(factory), TOTAL_AMOUNT);
        
        // Create ERC20 distributor with zero ETH - should succeed
        address distributorAddress = factory.createDistributor{value: 0}(
            address(token), 
            operator, 
            TOTAL_AMOUNT
        );
        vm.stopPrank();
        
        // Verify distributor was created successfully
        assertTrue(distributorAddress != address(0));
        assertTrue(factory.isDistributor(distributorAddress));
        assertEq(token.balanceOf(distributorAddress), TOTAL_AMOUNT);
    }
    function test_CreateERC20Distributor_WithoutValue_ShouldSucceed() public {
        // Create ERC20 token
        MockERC20 token = new MockERC20("Test Token", "TEST");
        token.mint(owner, TOTAL_AMOUNT);
        
        vm.startPrank(owner);
        token.approve(address(factory), TOTAL_AMOUNT);
        
        // Create ERC20 distributor without value - should succeed
        address distributorAddress = factory.createDistributor(
            address(token), 
            operator, 
            TOTAL_AMOUNT
        );
        vm.stopPrank();
        
        // Verify distributor was created successfully
        assertTrue(distributorAddress != address(0));
        assertTrue(factory.isDistributor(distributorAddress));
        assertEq(token.balanceOf(distributorAddress), TOTAL_AMOUNT);
    }

    function test_CreateNativeDistributor_WithETH_ShouldSucceed() public {
        uint256 ownerBalanceBefore = owner.balance;
        
        vm.startPrank(owner);
        address distributorAddress = factory.createDistributor{value: TOTAL_AMOUNT}(
            ETH_ADDRESS, 
            operator, 
            TOTAL_AMOUNT
        );
        vm.stopPrank();
        
        // Verify distributor was created successfully
        assertTrue(distributorAddress != address(0));
        assertTrue(factory.isDistributor(distributorAddress));
        assertEq(distributorAddress.balance, TOTAL_AMOUNT);
        assertEq(owner.balance, ownerBalanceBefore - TOTAL_AMOUNT);
    }
    
    function test_CreateNativeDistributor_WithoutETH_ShouldRevert() public {
        vm.startPrank(owner);
        
        // Try to create native distributor without ETH - should revert
        vm.expectRevert(DistributorFactory.AmountMismatch.selector);
        factory.createDistributor{value: 0}(
            ETH_ADDRESS, 
            operator, 
            TOTAL_AMOUNT
        );
        vm.stopPrank();
    }

    function test_CreateERC20Distributor_WithDifferentETHAmounts_ShouldRevert() public {
        // Create ERC20 token
        MockERC20 token = new MockERC20("Test Token", "TEST");
        token.mint(owner, TOTAL_AMOUNT);
        
        vm.startPrank(owner);
        token.approve(address(factory), TOTAL_AMOUNT);
        
        // Test with different ETH amounts - all should revert
        uint256[] memory ethAmounts = new uint256[](4);
        ethAmounts[0] = 1 wei;
        ethAmounts[1] = 0.001 ether;
        ethAmounts[2] = 1 ether;
        ethAmounts[3] = 10 ether;
        
        for (uint i = 0; i < ethAmounts.length; i++) {
            vm.expectRevert(DistributorFactory.UnexpectedNative.selector);
            factory.createDistributor{value: ethAmounts[i]}(
                address(token), 
                operator, 
                TOTAL_AMOUNT
            );
        }
        vm.stopPrank();
    }
    // ================================
    // Integration Tests
    // ================================
    
    function test_FullNativeWorkflow() public {
        // Create native distributor
        address distributorAddress = _createNativeDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));
        
        // Set up campaign
        uint256 startTime = block.timestamp + 1 hours;
        bytes32 merkleRoot = keccak256(abi.encodePacked(user1, USER_AMOUNT));
        
        vm.prank(operator);
        distributor.setTime(startTime);
        
        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot);
        
        // Fast forward to active period
        vm.warp(startTime + 1 hours);
        
        // User claims
        bytes32[] memory proof = new bytes32[](0);
        uint256 balanceBefore = user1.balance;
        
        vm.prank(user1);
        distributor.claim(USER_AMOUNT, proof);
        
        assertEq(user1.balance, balanceBefore + USER_AMOUNT);
        
        // Fast forward past end time
        vm.warp(startTime + 15 days);
        
        // Owner withdraws remaining
        uint256 ownerBalanceBefore = owner.balance;
        uint256 remainingBalance = distributorAddress.balance;
        
        vm.prank(owner);
        distributor.withdraw();
        
        assertEq(owner.balance, ownerBalanceBefore + remainingBalance);
        assertEq(distributorAddress.balance, 0);
    }
    
    function test_MixedNativeAndERC20Distributors() public {
        // Create native distributor
        address nativeDistributor = _createNativeDistributor();
        
        // Create ERC20 distributor (using mock token from existing test)
        MockERC20 token = new MockERC20("Test Token", "TEST");
        token.mint(owner, TOTAL_AMOUNT);
        
        vm.startPrank(owner);
        token.approve(address(factory), TOTAL_AMOUNT);
        address erc20Distributor = factory.createDistributor(address(token), operator, TOTAL_AMOUNT);
        vm.stopPrank();
        
        // Verify both distributors exist
        assertTrue(factory.isDistributor(nativeDistributor));
        assertTrue(factory.isDistributor(erc20Distributor));
        
        // Verify native distributor has ETH
        assertEq(nativeDistributor.balance, TOTAL_AMOUNT);
        
        // Verify ERC20 distributor has tokens
        assertEq(token.balanceOf(erc20Distributor), TOTAL_AMOUNT);
    }
}

// Helper contract that rejects ETH transfers
contract RejectingContract {
    receive() external payable {
        revert("Rejecting ETH");
    }
}

// Mock ERC20 token for testing
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        return true;
    }
}
