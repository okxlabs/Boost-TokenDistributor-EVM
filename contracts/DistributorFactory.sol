// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./TokenDistributor.sol";

/**
 * @title DistributorFactory - Token reward distribution factory contract
 * @notice This is a factory contract for reward distribution that allows anyone to configure token distributions
 * @dev Workflow:
 *      1. Anyone can call createDistributor to create a reward distribution contract
 *      2. Creation requires specifying token address, operator address, and total initial reward amount
 *      3. Factory contract automatically transfers tokens to the newly created distribution contract
 *      4. Operator can set merkle root, start time and duration in the distribution contract
 *      5. Users claim their rewards by providing merkle proofs during the distribution period
 *      6. Supports both ERC20 tokens and native tokens for distribution
 *      7. Distribution can be reopened by the operator after it ends
 */
contract DistributorFactory {
    using SafeERC20 for IERC20;

    // ============ Constant Variables ============

    /// @notice Native token identifier address
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // ============ Mutable State Variables ============

    /// @notice Check if an address is a distributor contract created by this factory
    mapping(address => bool) public isDistributor;

    // ============ Custom Errors ============

    // Custom errors for gas-efficient error handling
    error AmountMismatch(); // Amount mismatch
    error InvalidOperator(); // Invalid operator address
    error InvalidToken(); // Invalid token address
    error InvalidTotalAmount(); // Invalid total reward amount
    error NativeSendFailed(); // Native token send failed
    error UnexpectedNative(); // Unexpected Native token

    // ============ Events ============

    /**
     * @notice Emitted when a new distributor contract is created
     * @param owner Contract owner (creator)
     * @param operator Operator address (responsible for setting merkle root)
     * @param token Reward token address
     * @param distributorAddress Address of the newly created distributor contract
     */
    event DistributorCreated(
        address indexed owner, 
        address indexed operator, 
        address token, 
        address distributorAddress
    );

    // ============ Constructor ============

    constructor() {}

    // ============ External Functions ============

    /**
     * @notice Create a new reward distribution contract using CREATE2
     * @dev Anyone can call this function to create a reward distribution
     *      After creation, the specified amount of tokens will be automatically transferred to the new contract
     *      Uses CREATE2 with deterministic salt (includes token, amount, sender, chainId, and block number) for security
     *      Addresses will be different across chains due to chainId inclusion
     *      Same user can create multiple distributors in same block with different tokens or amounts
     * @param token Reward token address
     * @param operator Operator address, responsible for setting merkle root, start time and duration
     * @param initialTotalAmount Total reward amount, caller must have sufficient balance/approval for ERC20 or send native tokens
     * @return distributorAddress Address of the newly created distributor contract
     */
    function createDistributor(
        address token,
        address operator,
        uint256 initialTotalAmount
    ) external payable returns (address distributorAddress) {
        if (token == address(0)) revert InvalidToken();
        if (operator == address(0)) revert InvalidOperator();
        if (initialTotalAmount == 0) revert InvalidTotalAmount();

        // Generate deterministic salt using core parameters and environment variables
        // Note: Same user cannot create duplicate distributors (same token+amount) in the same block
        bytes32 salt = keccak256(abi.encodePacked(
            token,                         // Reward token address
            initialTotalAmount,            // Total reward amount
            msg.sender,                    // Creator address
            block.chainid,                 // Current chain ID
            block.number                   // Current block number
        ));

        // Create distributor contract instance using CREATE2
        distributorAddress = address(new TokenDistributor{salt: salt}(
            msg.sender,        // owner: contract owner, can withdraw remaining tokens
            operator,          // operator: administrator, can set merkle root, start time and duration
            token              // token: reward token address
        ));
        if (token == ETH_ADDRESS) {
            // Validate that caller sent the exact amount required for Native token distribution
            if (msg.value != initialTotalAmount) revert AmountMismatch();

            // Transfer Native token to the distribution contract
            (bool success, ) = payable(distributorAddress).call{value: initialTotalAmount}("");
            if (!success) revert NativeSendFailed();
        } else {
            // Validate that caller did not send Native token
            if(msg.value > 0) revert UnexpectedNative();
            // Transfer tokens from creator to the distribution contract
            IERC20(token).safeTransferFrom(msg.sender, distributorAddress, initialTotalAmount);
        }

        // Record the newly created distribution contract
        isDistributor[distributorAddress] = true;

        // Emit event
        emit DistributorCreated(msg.sender, operator, token, distributorAddress);
    }
}
