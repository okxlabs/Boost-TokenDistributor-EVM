// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./TokenDistributor.sol";

/**
 * @title DistributorFactory - Token reward distribution factory contract
 * @notice This is a factory contract for reward distribution that allows anyone to configure token distributions
 * @dev Workflow:
 *      1. Anyone can call createDistributor to create a reward distribution contract
 *      2. Creation requires specifying token address, operator address, and total reward amount
 *      3. Factory contract automatically transfers tokens to the newly created distribution contract
 *      4. Operator can set merkle root in the distribution contract
 *      5. Users claim their rewards by providing merkle proofs
 */
contract DistributorFactory {
    using SafeERC20 for IERC20;

    /// @notice Check if an address is a distributor contract created by this factory
    mapping(address => bool) public isDistributor;

    // Custom errors for gas-efficient error handling
    error InvalidOperator(); // Invalid operator address
    error InvalidToken(); // Invalid token address
    error InvalidTotalAmount(); // Invalid total reward amount

    /**
     * @notice Emitted when a new distributor contract is created
     * @param owner Contract owner (creator)
     * @param operator Operator address (responsible for setting merkle root)
     * @param token Reward token address
     * @param distributorAddress Address of the newly created distributor contract
     */
    event DistributorCreated(address indexed owner, address indexed operator, address token, address distributorAddress);

    /**
     * @notice Create a new reward distribution contract
     * @dev Anyone can call this function to create a reward distribution
     *      After creation, the specified amount of tokens will be automatically transferred to the new contract
     * @param token Reward token address
     * @param operator Operator address, responsible for setting merkle root and start time
     * @param initialTotalAmount Total reward amount, caller must have sufficient token balance and approval
     * @return distributorAddress Address of the newly created distributor contract
     */
    function createDistributor(address token, address operator, uint256 initialTotalAmount) external returns (address distributorAddress) {
        if (token == address(0)) revert InvalidToken();
        if (operator == address(0)) revert InvalidOperator();
        if (initialTotalAmount == 0) revert InvalidTotalAmount();

        // Create distributor contract instance
        // msg.sender becomes the contract owner, operator becomes the administrator
        distributorAddress = address(
            new TokenDistributor(
                msg.sender, // owner: contract owner, can withdraw remaining tokens
                operator, // operator: administrator, can set merkle root and start time
                token, // token: reward token address
                initialTotalAmount // initialTotalAmount: total reward amount
            )
        );

        // Transfer tokens from creator to the distribution contract
        IERC20(token).safeTransferFrom(msg.sender, distributorAddress, initialTotalAmount);

        // Record the newly created distribution contract
        isDistributor[distributorAddress] = true;

        // Emit event
        emit DistributorCreated(msg.sender, operator, token, distributorAddress);
    }
}
