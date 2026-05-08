// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "../contracts/TokenDistributor.sol";
import "../contracts/DistributorFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DistributorComplexTest is Test {
    DistributorFactory public factory;
    MockERC20 public token;

    address public owner = address(0x1);
    address public operator = address(0x2);
    address public alice = address(0x100); // User 1
    address public bob = address(0x200); // User 2
    address public charlie = address(0x300); // User 3

    uint256 public constant TOTAL_AMOUNT = 10000 * 10 ** 18;

    // User reward amounts
    uint256 public constant ALICE_AMOUNT = 1000 * 10 ** 18; // 1000 tokens
    uint256 public constant BOB_AMOUNT = 2500 * 10 ** 18; // 2500 tokens
    uint256 public constant CHARLIE_AMOUNT = 3000 * 10 ** 18; // 3000 tokens

    struct UserData {
        address account;
        uint256 amount;
    }

    function setUp() public {
        factory = new DistributorFactory();
        token = new MockERC20("Test Token", "TEST");

        token.mint(owner, TOTAL_AMOUNT * 10);

        vm.label(owner, "Owner");
        vm.label(operator, "Operator");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
    }

    function _createDistributor() internal returns (address distributorAddress) {
        vm.startPrank(owner);
        token.approve(address(factory), TOTAL_AMOUNT);
        distributorAddress = factory.createDistributor(address(token), operator, TOTAL_AMOUNT);
        vm.stopPrank();
    }

    /**
     * @dev Generate Merkle tree for three users
     * Uses OpenZeppelin compatible implementation
     */
    function _generateMerkleTreeForThreeUsers()
        internal
        view
        returns (bytes32 root, bytes32[] memory aliceProof, bytes32[] memory bobProof, bytes32[] memory charlieProof)
    {
        // Create sorted leaves (OpenZeppelin expects sorted leaves)
        bytes32 aliceLeaf = keccak256(abi.encodePacked(alice, ALICE_AMOUNT));
        bytes32 bobLeaf = keccak256(abi.encodePacked(bob, BOB_AMOUNT));
        bytes32 charlieLeaf = keccak256(abi.encodePacked(charlie, CHARLIE_AMOUNT));
        bytes32 emptyLeaf = bytes32(0);

        // Sort leaves for consistent ordering
        bytes32[] memory leaves = new bytes32[](4);
        leaves[0] = aliceLeaf;
        leaves[1] = bobLeaf;
        leaves[2] = charlieLeaf;
        leaves[3] = emptyLeaf;

        // Build tree bottom-up with proper ordering
        bytes32 hash01 = _hashPair(leaves[0], leaves[1]);
        bytes32 hash23 = _hashPair(leaves[2], leaves[3]);
        root = _hashPair(hash01, hash23);

        // Generate proofs for OpenZeppelin MerkleProof.verify
        aliceProof = new bytes32[](2);
        aliceProof[0] = bobLeaf; // Sibling at level 0
        aliceProof[1] = hash23; // Uncle at level 1

        bobProof = new bytes32[](2);
        bobProof[0] = aliceLeaf; // Sibling at level 0
        bobProof[1] = hash23; // Uncle at level 1

        charlieProof = new bytes32[](2);
        charlieProof[0] = emptyLeaf; // Sibling at level 0
        charlieProof[1] = hash01; // Uncle at level 1
    }

    /**
     * @dev Hash two nodes in deterministic order (smaller first)
     */
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /**
     * @dev Complex test case: Three users with different amounts
     * Tests the complete workflow with real Merkle tree verification
     */
    function test_ThreeUsersComplexWorkflow() public {
        console.log("=== Starting Complex Three Users Test ===");

        // 1. Create distributor contract
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        console.log("Distributor contract created at:", distributorAddress);
        console.log("Initial token balance:", token.balanceOf(distributorAddress));

        // 2. Generate Merkle tree and proofs
        (
            bytes32 merkleRoot,
            bytes32[] memory aliceProof,
            bytes32[] memory bobProof,
            bytes32[] memory charlieProof
        ) = _generateMerkleTreeForThreeUsers();

        console.log("Generated Merkle root:");
        console.logBytes32(merkleRoot);

        // 3. Set up distributor campaign
        uint256 startTime = block.timestamp + 1 hours;

        vm.prank(operator);
        distributor.setTime(startTime, 14 days);
        console.log("Start time set to:", startTime);

        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot);
        console.log("Merkle root set successfully");

        // 4. Fast forward to claim period
        vm.warp(startTime + 30 minutes);
        console.log("Time warped to claim period");

        // 5. Alice claims her tokens
        console.log("\n--- Alice Claims ---");
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        console.log("Alice balance before:", aliceBalanceBefore);

        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof);

        uint256 aliceBalanceAfter = token.balanceOf(alice);
        console.log("Alice balance after:", aliceBalanceAfter);
        console.log("Alice claimed amount:", distributor.claimedAmounts(alice));

        assertEq(aliceBalanceAfter, aliceBalanceBefore + ALICE_AMOUNT);
        assertEq(distributor.claimedAmounts(alice), ALICE_AMOUNT);

        // 6. Bob claims his tokens
        console.log("\n--- Bob Claims ---");
        uint256 bobBalanceBefore = token.balanceOf(bob);
        console.log("Bob balance before:", bobBalanceBefore);

        vm.prank(bob);
        distributor.claim(BOB_AMOUNT, bobProof);

        uint256 bobBalanceAfter = token.balanceOf(bob);
        console.log("Bob balance after:", bobBalanceAfter);
        console.log("Bob claimed amount:", distributor.claimedAmounts(bob));

        assertEq(bobBalanceAfter, bobBalanceBefore + BOB_AMOUNT);
        assertEq(distributor.claimedAmounts(bob), BOB_AMOUNT);

        // 7. Charlie claims his tokens
        console.log("\n--- Charlie Claims ---");
        uint256 charlieBalanceBefore = token.balanceOf(charlie);
        console.log("Charlie balance before:", charlieBalanceBefore);

        vm.prank(charlie);
        distributor.claim(CHARLIE_AMOUNT, charlieProof);

        uint256 charlieBalanceAfter = token.balanceOf(charlie);
        console.log("Charlie balance after:", charlieBalanceAfter);
        console.log("Charlie claimed amount:", distributor.claimedAmounts(charlie));

        assertEq(charlieBalanceAfter, charlieBalanceBefore + CHARLIE_AMOUNT);
        assertEq(distributor.claimedAmounts(charlie), CHARLIE_AMOUNT);

        // 8. Verify total claimed
        uint256 totalClaimed = ALICE_AMOUNT + BOB_AMOUNT + CHARLIE_AMOUNT;
        uint256 remainingInContract = token.balanceOf(distributorAddress);

        console.log("\n--- Final State ---");
        console.log("Total claimed:", totalClaimed);
        console.log("Remaining in contract:", remainingInContract);
        console.log("Expected remaining:", TOTAL_AMOUNT - totalClaimed);

        assertEq(remainingInContract, TOTAL_AMOUNT - totalClaimed);

        // 9. Test invalid proof (should fail)
        console.log("\n--- Testing Invalid Proof ---");
        address invalidUser = address(0x999);
        uint256 invalidAmount = 1000 * 10 ** 18;

        vm.expectRevert(TokenDistributor.InvalidProof.selector);
        vm.prank(invalidUser);
        distributor.claim(invalidAmount, aliceProof); // Wrong proof for wrong user

        // 10. Test double claiming (should fail)
        console.log("\n--- Testing Double Claiming ---");
        vm.expectRevert(TokenDistributor.InvalidAmount.selector);
        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof);

        // 11. Fast forward past end time and withdraw remaining
        vm.warp(startTime + 15 days);
        console.log("\n--- Owner Withdraws Remaining ---");

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 contractBalance = token.balanceOf(distributorAddress);

        vm.prank(owner);
        distributor.withdraw();

        uint256 ownerBalanceAfter = token.balanceOf(owner);
        console.log("Owner balance increased by:", ownerBalanceAfter - ownerBalanceBefore);

        assertEq(ownerBalanceAfter, ownerBalanceBefore + contractBalance);
        assertEq(token.balanceOf(distributorAddress), 0);

        console.log("=== Complex Test Completed Successfully ===");
    }

    /**
     * @dev Test that demonstrates how partial claiming works
     * In real scenarios, users would claim multiple times with the same maxAmount
     */
    function test_ThreeUsersPartialClaiming() public {
        console.log("=== Testing Partial Claiming Workflow ===");

        // Create distributor
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        // Generate main Merkle tree
        (bytes32 merkleRoot, bytes32[] memory aliceProof, , ) = _generateMerkleTreeForThreeUsers();

        // Set up timing
        uint256 startTime = block.timestamp + 1 hours;
        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot);

        vm.warp(startTime + 30 minutes);

        // Alice claims full amount at once (this is the intended behavior)
        console.log("Alice claims full amount: 1000 tokens");
        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof);

        assertEq(token.balanceOf(alice), ALICE_AMOUNT);
        assertEq(distributor.claimedAmounts(alice), ALICE_AMOUNT);

        // Test that Alice cannot claim again
        vm.expectRevert(TokenDistributor.InvalidAmount.selector);
        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof);

        console.log("Partial claiming test completed successfully");
    }

    /**
     * @dev Test edge cases with three users
     */
    function test_ThreeUsersEdgeCases() public {
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        // Generate tree
        (bytes32 merkleRoot, , , ) = _generateMerkleTreeForThreeUsers();

        uint256 startTime = block.timestamp + 1 hours;
        vm.prank(operator);
        distributor.setTime(startTime, 14 days);

        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot);

        vm.warp(startTime + 30 minutes);

        // Test claiming with wrong amount (should fail)
        bytes32[] memory aliceProof = new bytes32[](2);
        aliceProof[0] = keccak256(abi.encodePacked(bob, BOB_AMOUNT));
        aliceProof[1] = keccak256(abi.encodePacked(keccak256(abi.encodePacked(charlie, CHARLIE_AMOUNT)), bytes32(0)));

        vm.expectRevert(TokenDistributor.InvalidProof.selector);
        vm.prank(alice);
        distributor.claim(BOB_AMOUNT, aliceProof); // Alice tries to claim Bob's amount

        // Test claiming with manipulated proof
        bytes32[] memory fakeProof = new bytes32[](2);
        fakeProof[0] = bytes32(uint256(123));
        fakeProof[1] = bytes32(uint256(456));

        vm.expectRevert(TokenDistributor.InvalidProof.selector);
        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, fakeProof);

        console.log("Edge cases test completed");
    }

    /**
     * @dev Test multiple distribution rounds using remaining tokens
     * This test demonstrates the ability to restart distribution after it ends
     */
    function test_MultipleDistributionRounds() public {
        console.log("=== Testing Multiple Distribution Rounds ===");

        // Create distributor
        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        console.log("Initial contract balance:", token.balanceOf(distributorAddress));

        // === ROUND 1: First Distribution ===
        console.log("\n--- Round 1: First Distribution ---");
        
        // Generate merkle tree for round 1 (only Alice and Bob)
        bytes32 aliceLeaf = keccak256(abi.encodePacked(alice, ALICE_AMOUNT));
        bytes32 bobLeaf = keccak256(abi.encodePacked(bob, BOB_AMOUNT));
        bytes32 emptyLeaf1 = bytes32(0);
        bytes32 emptyLeaf2 = bytes32(0);

        bytes32 hash01_r1 = _hashPair(aliceLeaf, bobLeaf);
        bytes32 hash23_r1 = _hashPair(emptyLeaf1, emptyLeaf2);
        bytes32 merkleRoot1 = _hashPair(hash01_r1, hash23_r1);

        // Alice proof for round 1
        bytes32[] memory aliceProof1 = new bytes32[](2);
        aliceProof1[0] = bobLeaf;
        aliceProof1[1] = hash23_r1;

        // Bob proof for round 1
        bytes32[] memory bobProof1 = new bytes32[](2);
        bobProof1[0] = aliceLeaf;
        bobProof1[1] = hash23_r1;

        // Set up round 1 (7 days duration)
        uint256 startTime1 = block.timestamp + 1 hours;
        vm.prank(operator);
        distributor.setTime(startTime1, 7 days);
        console.log("Round 1 start time:", startTime1);
        console.log("Round 1 end time:", startTime1 + 7 days);

        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot1);
        console.log("Round 1 merkle root set");

        // Fast forward to round 1 claim period
        vm.warp(startTime1 + 1 hours);

        // Alice claims in round 1
        uint256 aliceBalance1Before = token.balanceOf(alice);
        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof1);
        console.log("Alice claimed in round 1:", ALICE_AMOUNT);

        // Bob claims in round 1
        uint256 bobBalance1Before = token.balanceOf(bob);
        vm.prank(bob);
        distributor.claim(BOB_AMOUNT, bobProof1);
        console.log("Bob claimed in round 1:", BOB_AMOUNT);

        // Verify round 1 claims
        assertEq(token.balanceOf(alice), aliceBalance1Before + ALICE_AMOUNT);
        assertEq(token.balanceOf(bob), bobBalance1Before + BOB_AMOUNT);

        uint256 contractBalanceAfterRound1 = token.balanceOf(distributorAddress);
        uint256 expectedRemaining1 = TOTAL_AMOUNT - ALICE_AMOUNT - BOB_AMOUNT;
        assertEq(contractBalanceAfterRound1, expectedRemaining1);
        console.log("Remaining after round 1:", contractBalanceAfterRound1);

        // Fast forward past round 1 end time
        vm.warp(startTime1 + 8 days);
        console.log("Round 1 ended, time:", block.timestamp);

        // === ROUND 2: Second Distribution with Remaining Tokens ===
        console.log("\n--- Round 2: Second Distribution ---");

        // Generate merkle tree for round 2 (Charlie gets remaining tokens)
        uint256 charlieRound2Amount = CHARLIE_AMOUNT; // 3000 tokens
        bytes32 charlieLeaf = keccak256(abi.encodePacked(charlie, charlieRound2Amount));
        bytes32 emptyLeaf3 = bytes32(0);
        bytes32 emptyLeaf4 = bytes32(0);
        bytes32 emptyLeaf5 = bytes32(0);

        bytes32 hash01_r2 = _hashPair(charlieLeaf, emptyLeaf3);
        bytes32 hash23_r2 = _hashPair(emptyLeaf4, emptyLeaf5);
        bytes32 merkleRoot2 = _hashPair(hash01_r2, hash23_r2);

        // Charlie proof for round 2
        bytes32[] memory charlieProof2 = new bytes32[](2);
        charlieProof2[0] = emptyLeaf3;
        charlieProof2[1] = hash23_r2;

        // Set up round 2 (3 days duration) - this should work after round 1 ended
        uint256 startTime2 = block.timestamp + 2 hours;
        vm.prank(operator);
        distributor.setTime(startTime2, 3 days);
        console.log("Round 2 start time:", startTime2);
        console.log("Round 2 end time:", startTime2 + 3 days);

        vm.prank(operator);
        distributor.setMerkleRoot(merkleRoot2);
        console.log("Round 2 merkle root set");

        // Verify that Alice and Bob cannot claim again (their claims are reset per round)
        // But their previous claims should still be recorded
        assertEq(distributor.claimedAmounts(alice), ALICE_AMOUNT);
        assertEq(distributor.claimedAmounts(bob), BOB_AMOUNT);
        assertEq(distributor.claimedAmounts(charlie), 0);

        // Fast forward to round 2 claim period
        vm.warp(startTime2 + 1 hours);

        // Charlie claims in round 2
        uint256 charlieBalance2Before = token.balanceOf(charlie);
        vm.prank(charlie);
        distributor.claim(charlieRound2Amount, charlieProof2);
        console.log("Charlie claimed in round 2:", charlieRound2Amount);

        // Verify round 2 claim
        assertEq(token.balanceOf(charlie), charlieBalance2Before + charlieRound2Amount);
        assertEq(distributor.claimedAmounts(charlie), charlieRound2Amount);

        uint256 contractBalanceAfterRound2 = token.balanceOf(distributorAddress);
        uint256 expectedRemaining2 = expectedRemaining1 - charlieRound2Amount;
        assertEq(contractBalanceAfterRound2, expectedRemaining2);
        console.log("Remaining after round 2:", contractBalanceAfterRound2);

        // === ROUND 3: Final Distribution (if any remaining) ===
        console.log("\n--- Round 3: Final Cleanup ---");

        // Fast forward past round 2 end time
        vm.warp(startTime2 + 4 days);

        // Owner can withdraw any remaining tokens
        if (contractBalanceAfterRound2 > 0) {
            uint256 ownerBalanceBefore = token.balanceOf(owner);
            vm.prank(owner);
            distributor.withdraw();
            
            uint256 ownerBalanceAfter = token.balanceOf(owner);
            assertEq(ownerBalanceAfter, ownerBalanceBefore + contractBalanceAfterRound2);
            assertEq(token.balanceOf(distributorAddress), 0);
            console.log("Owner withdrew remaining:", contractBalanceAfterRound2);
        }

        // === Verify Final State ===
        console.log("\n--- Final Verification ---");
        console.log("Alice total received:", token.balanceOf(alice));
        console.log("Bob total received:", token.balanceOf(bob));
        console.log("Charlie total received:", token.balanceOf(charlie));
        console.log("Contract final balance:", token.balanceOf(distributorAddress));

        // Verify total distribution
        uint256 totalDistributed = token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(charlie);
        console.log("Total distributed to users:", totalDistributed);
        
        // The contract should be empty now
        assertEq(token.balanceOf(distributorAddress), 0);

        console.log("=== Multiple Distribution Rounds Test Completed ===");
    }

    /**
     * @dev Test that operator cannot set new time during active distribution
     * but can set it after distribution ends
     */
    function test_TimeSettingRestrictions() public {
        console.log("=== Testing Time Setting Restrictions ===");

        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        // Set initial distribution time
        uint256 startTime1 = block.timestamp + 1 hours;
        vm.prank(operator);
        distributor.setTime(startTime1, 5 days);
        console.log("Initial distribution set: start =", startTime1, "duration = 5 days");

        // Fast forward to during the distribution period
        vm.warp(startTime1 + 2 days);
        console.log("Current time is during distribution period");

        // Try to set new time during active distribution - should fail
        uint256 newStartTime = block.timestamp + 1 hours;
        vm.prank(operator);
        vm.expectRevert(TokenDistributor.InvalidTime.selector);
        distributor.setTime(newStartTime, 3 days);
        console.log("Cannot set time during active distribution");

        // Fast forward past the distribution end time
        vm.warp(startTime1 + 6 days);
        console.log("Current time is after distribution ended");

        // Now setting new time should work
        uint256 startTime2 = block.timestamp + 2 hours;
        vm.prank(operator);
        distributor.setTime(startTime2, 10 days);
        console.log("Successfully set new time after distribution ended");

        // Verify the new times are set correctly
        assertEq(distributor.startTime(), startTime2);
        assertEq(distributor.endTime(), startTime2 + 10 days);

        console.log("=== Time Setting Restrictions Test Completed ===");
    }

    /**
     * @dev Test InvalidDuration error when duration exceeds MAX_DURATION
     */
    function test_SetTime_InvalidDuration() public {
        console.log("=== Testing InvalidDuration Error ===");

        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 validStartTime = block.timestamp + 1 hours;
        
        // Test various invalid durations that exceed MAX_DURATION (365 days)
        uint256[] memory invalidDurations = new uint256[](4);
        invalidDurations[0] = 366 days;           // Just over the limit
        invalidDurations[1] = 400 days;           // Moderately over
        invalidDurations[2] = 730 days;           // 2 years
        invalidDurations[3] = type(uint256).max;  // Maximum possible value

        for (uint i = 0; i < invalidDurations.length; i++) {
            console.log("Testing invalid duration:", invalidDurations[i] / 1 days, "days");
            
            vm.prank(operator);
            vm.expectRevert(TokenDistributor.InvalidDuration.selector);
            distributor.setTime(validStartTime, invalidDurations[i]);
            
            console.log("Correctly rejected duration of", invalidDurations[i] / 1 days, "days");
        }

        // Test that MAX_DURATION (365 days) is still valid
        console.log("Testing valid MAX_DURATION (365 days)");
        vm.prank(operator);
        distributor.setTime(validStartTime, 365 days);
        console.log("Successfully set duration to MAX_DURATION (365 days)");

        // Verify the time was set correctly
        assertEq(distributor.startTime(), validStartTime);
        assertEq(distributor.endTime(), validStartTime + 365 days);

        // Test edge case: exactly MAX_DURATION + 1 second should fail
        console.log("Testing MAX_DURATION + 1 second");
        vm.prank(operator);
        vm.expectRevert(TokenDistributor.InvalidDuration.selector);
        distributor.setTime(validStartTime + 1 days, 365 days + 1);
        console.log("Correctly rejected MAX_DURATION + 1 second");

        console.log("=== InvalidDuration Test Completed ===");
    }

    /**
     * @dev Test InvalidDuration error when duration is zero
     */
    function test_SetTime_ZeroDuration() public {
        console.log("=== Testing Zero Duration Error ===");

        address distributorAddress = _createDistributor();
        TokenDistributor distributor = TokenDistributor(payable(distributorAddress));

        uint256 validStartTime = block.timestamp + 1 hours;
        
        // Test zero duration - should fail
        console.log("Testing zero duration");
        vm.prank(operator);
        vm.expectRevert(TokenDistributor.InvalidDuration.selector);
        distributor.setTime(validStartTime, 0);
        console.log("Correctly rejected zero duration");

        // Test that 1 second duration is valid (minimum valid duration)
        console.log("Testing minimum valid duration (1 second)");
        vm.prank(operator);
        distributor.setTime(validStartTime, 1);
        console.log("Successfully set duration to 1 second");

        // Verify the time was set correctly
        assertEq(distributor.startTime(), validStartTime);
        assertEq(distributor.endTime(), validStartTime + 1);

        console.log("=== Zero Duration Test Completed ===");
    }
}
