// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TokenDistributor - Merkle tree based token distribution contract
 * @notice This contract allows users to claim tokens based on merkle proofs
 * @dev The contract uses merkle trees to efficiently distribute tokens to a large number of recipients
 *      Operator sets merkle root and start time, owner withdraws remaining tokens when distribution ends or hasn't started
 *      Supports both ERC20 tokens and native tokens for distribution
 */
contract TokenDistributor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Distribution period duration (14 days)
    uint256 public constant DURATION = 14 days;

    /// @notice Maximum allowed start time offset from current time (90 days)
    uint256 public constant MAX_START_TIME = 90 days;

    /// @notice Native token identifier address
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // ============ Immutable Variables ============

    /// @notice Address of the token being distributed
    address public immutable token;

    /// @notice Init Total amount of tokens to be distributed
    uint256 public immutable initialTotalAmount;

    /// @notice Address authorized to set merkle root and start time
    address public immutable operator;

    /// @notice Address authorized to withdraw remaining tokens
    address public immutable owner;

    // ============ Mutable State Variables ============

    /// @notice Merkle root hash for validating claims
    bytes32 public merkleRoot;

    /// @notice Total amount of tokens claimed
    uint256 public totalClaimed;

    /// @notice Timestamp when the distribution starts
    /// @notice Timestamp when the distribution ends
    /// @dev Packed together to save storage slot and reduce gas cost
    uint64 public startTime;
    uint64 public endTime;

    /// @notice Mapping of addresses to their claimed amounts
    mapping(address => uint256) public claimedAmounts;

    // Custom errors for gas-efficient error handling
    error AlreadyStarted(); // It has already started
    error InvalidAmount(); // Amount cannot be zero
    error InvalidProof(); // Invalid merkle proof
    error InvalidRoot(); // Invalid merkle root
    error InvalidTime(); // Invalid timestamp
    error NativeSendFailed(); // Native token send failed
    error NativeNotAccepted(); // Native token not accepted
    error NoRoot(); // Merkle root not set
    error NoTokens(); // No tokens available
    error OnlyOperator(); // Only operator can call this function
    error OnlyOwner(); // Only owner can call this function
    error StartTimeNotSet(); // Start time not set
    error TooEarly(); // Distribution hasn't started yet
    error TooLate(); // Distribution has ended

    /// @notice Emitted when start time is set
    event TimeSet(uint64 startTime, uint64 endTime);

    /// @notice Emitted when merkle root is set
    event MerkleRootSet(bytes32 merkleRoot);

    /// @notice Emitted when tokens are claimed
    event Claimed(address indexed account, uint256 amount);

    /// @notice Emitted when remaining tokens are withdrawn
    event Withdrawn(address to, uint256 amount);

    /// @notice Restricts access to operator only
    modifier onlyOperator() {
        if (msg.sender != operator) revert OnlyOperator();
        _;
    }

    /// @notice Restricts access to owner only
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    /// @notice Initialize distributor contract
    /// @param _owner Owner address who can withdraw remaining tokens
    /// @param _operator Operator address who can set merkle root and start time
    /// @param _token Token address to be distributed
    /// @param _initialTotalAmount Initial Total amount of tokens to be distributed
    constructor(address _owner, address _operator, address _token, uint256 _initialTotalAmount) {
        owner = _owner;
        operator = _operator;
        token = _token;
        initialTotalAmount = _initialTotalAmount;
    }

    /// @notice Set airdrop start time
    /// @dev Can be called multiple times by the operator with the following restrictions:
    /// 1. Cannot be set if distribution has already started
    /// 2. Start time must be greater than current block timestamp
    /// 3. Start time must be less than or equal to current time + 90 days
    /// 4. Can be set multiple times as long as distribution hasn't started
    /// @param _startTime Start timestamp (must be in the future but within MAX_START_TIME)
    function setTime(uint256 _startTime) external onlyOperator {
        if (_startTime <= block.timestamp) revert InvalidTime();
        if (_startTime > block.timestamp + MAX_START_TIME) revert InvalidTime();
        if (block.timestamp >= startTime && startTime > 0) revert AlreadyStarted();

        startTime = uint64(_startTime);
        endTime = uint64(_startTime + DURATION);

        emit TimeSet(startTime, endTime);
    }

    /// @notice Set merkle root for claim validation
    /// @dev Can be called multiple times by the operator to update the merkle root
    /// @param _merkleRoot Merkle root hash
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOperator {
        if (_merkleRoot == bytes32(0)) revert InvalidRoot();
        merkleRoot = _merkleRoot;

        emit MerkleRootSet(_merkleRoot);
    }

    /// @notice Withdraw remaining tokens after distribution ends
    /// @dev Can only be called by owner after the distribution period ends or not set the startTime
    function withdraw() external onlyOwner {
        // Check if distribution has ended or not set the startTime
        if (block.timestamp <= endTime) revert InvalidTime();

        uint256 balance = getBalance();
        if (balance == 0) revert NoTokens();

        transfer(msg.sender, balance);

        emit Withdrawn(msg.sender, balance);
    }

    /// @notice Claim reward tokens using merkle proof
    /// @dev Supports single claim (when root set once) or incremental distributions
    ///      by adjusting maxAmount without resetting previous claims
    /// @param maxAmount Maximum claimable amount for this address (from merkle tree)
    /// @param proof Merkle proof to validate the claim
    function claim(uint256 maxAmount, bytes32[] calldata proof) external nonReentrant {
        // Validate distribution state
        if (startTime == 0) revert StartTimeNotSet();
        if (block.timestamp < startTime) revert TooEarly();
        if (block.timestamp > endTime) revert TooLate();
        if (merkleRoot == bytes32(0)) revert NoRoot();

        // Check if user has already claimed the maximum amount
        uint256 claimedAmount = claimedAmounts[msg.sender];
        if (maxAmount <= claimedAmount) revert InvalidAmount();

        // Verify merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, maxAmount));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert InvalidProof();

        // Calculate pending amount to claim
        uint256 pendingAmount;
        unchecked {
            pendingAmount = maxAmount - claimedAmount; // Safe: maxAmount > claimedAmount verified above
        }

        // Update claimed amount before transfer (CEI pattern)
        claimedAmounts[msg.sender] = maxAmount;

        // Update total claimed amount
        totalClaimed += pendingAmount;

        // Transfer tokens to claimant
        transfer(msg.sender, pendingAmount);

        emit Claimed(msg.sender, pendingAmount);
    }

    
    /// @notice Get the balance of the contract
    function getBalance() internal view returns (uint256) {
        if (token == ETH_ADDRESS) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    /// @notice Transfer tokens to a given address
    function transfer(address to, uint256 amount) internal {
        if (token == ETH_ADDRESS) {
            (bool success, ) = payable(to).call{value: amount, gas: 5000}("");
            if (!success) revert NativeSendFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /// @dev Accept Native Token
    receive() external payable {
        if(token != ETH_ADDRESS) revert NativeNotAccepted();
    }
}
