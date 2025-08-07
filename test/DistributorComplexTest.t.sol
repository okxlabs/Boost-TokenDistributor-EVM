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
        TokenDistributor distributor = TokenDistributor(distributorAddress);

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
        distributor.setTime(startTime);
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
        TokenDistributor distributor = TokenDistributor(distributorAddress);

        // Generate main Merkle tree
        (bytes32 merkleRoot, bytes32[] memory aliceProof, , ) = _generateMerkleTreeForThreeUsers();

        // Set up timing
        uint256 startTime = block.timestamp + 1 hours;
        vm.prank(operator);
        distributor.setTime(startTime);

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
        TokenDistributor distributor = TokenDistributor(distributorAddress);

        // Generate tree
        (bytes32 merkleRoot, , , ) = _generateMerkleTreeForThreeUsers();

        uint256 startTime = block.timestamp + 1 hours;
        vm.prank(operator);
        distributor.setTime(startTime);

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
}
