# Token Distributor

This repository provides comprehensive documentation and example smart contracts for TokenDistributor - a sophisticated token distribution platform built with security, gas efficiency, and scalability in mind.

## Project Structure

```
contracts/
├── DistributorFactory.sol    # Factory contract for creating token distributors
└── TokenDistributor.sol      # Core distribution contract with Merkle tree verification

test/
├── DistributorTest.t.sol     # Comprehensive unit and integration tests
└── DistributorComplexTest.t.sol  # Advanced tests with real Merkle tree verification
```

## Smart Contracts

### DistributorFactory.sol

A factory contract that allows anyone to create token distribution campaigns.

**Key Features:**
- **Factory Pattern**: Creates new `TokenDistributor` instances
- **Token Transfer**: Automatically transfers tokens from creator to distributor contract
- **Access Control**: Validates token address, operator address, and total amount
- **Event Tracking**: Emits `DistributorCreated` events for transparency

**Core Functions:**
- `createDistributor(address token, address operator, uint256 initialTotalAmount)` - Creates a new distributor contract

**Security Features:**
- Custom errors for gas-efficient error handling
- Input validation for zero addresses and amounts
- SafeERC20 for secure token transfers

### TokenDistributor.sol

A Merkle tree-based token distribution contract with advanced features.

**Key Features:**
- **Merkle Tree Verification**: Efficient distribution to large recipient lists
- **Time-based Distribution**: Configurable start/end times with 14-day duration
- **Incremental Claims**: Support for partial claiming and distribution updates
- **Access Control**: Separate owner and operator roles
- **Reentrancy Protection**: Uses OpenZeppelin's ReentrancyGuard

**Core Functions:**
- `setTime(uint256 _startTime)` - Set distribution start time (operator only)
- `setMerkleRoot(bytes32 _merkleRoot)` - Set Merkle root for claim validation (operator only)
- `claim(uint256 maxAmount, bytes32[] calldata proof)` - Claim tokens using Merkle proof
- `withdraw()` - Withdraw remaining tokens after distribution ends (owner only)

**Security Features:**
- Checks-Effects-Interactions pattern
- Custom errors for gas efficiency
- Time validation (max 90 days future start time)
- Merkle proof verification using OpenZeppelin's library
- Immutable variables for critical parameters

**Constants:**
- `DURATION = 14 days` - Distribution period length
- `MAX_START_TIME = 90 days` - Maximum future start time

## Test Suite

### DistributorTest.t.sol

Comprehensive test suite covering all contract functionality.

**Test Categories:**

**Factory Tests:**
- Successful distributor creation
- Input validation (invalid token, operator, amounts)
- Insufficient allowance handling

**Distributor Core Tests:**
- Constructor parameter validation
- Time setting functionality and restrictions
- Merkle root setting and updates
- Claim functionality with various scenarios
- Withdrawal functionality and access control

**Integration Tests:**
- Complete workflow from creation to withdrawal
- Multiple user scenarios
- Partial claiming functionality

**Edge Cases:**
- Invalid proofs and amounts
- Double claiming prevention
- Time-based restrictions
- Access control validation

### DistributorComplexTest.t.sol

Advanced test suite with real Merkle tree implementation.

**Key Features:**
- **Real Merkle Tree**: Implements actual Merkle tree generation and proof verification
- **Multi-user Scenarios**: Tests with three users (Alice, Bob, Charlie) with different amounts
- **Complex Workflows**: End-to-end testing with realistic distribution scenarios
- **Proof Validation**: Tests both valid and invalid Merkle proofs
- **Partial Claiming**: Demonstrates incremental distribution capabilities

**Test Scenarios:**
- Three users with different token amounts (1000, 2500, 3000 tokens)
- Complete workflow from creation to final withdrawal
- Invalid proof rejection
- Double claiming prevention
- Edge case handling

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) (for Solidity contract development)
- [Node.js](https://nodejs.org/) (for documentation tooling, if needed)

### Usage

- Run tests using `forge test` for comprehensive testing
- Use `forge test -vv` for verbose output with detailed logs
- Explore smart contracts in the `contracts/` directory
- Review test implementations for usage examples

### Key Features

**Security:**
- Reentrancy protection
- Access control with separate owner/operator roles
- Merkle tree verification for efficient distribution
- Time-based restrictions and validation

**Gas Efficiency:**
- Custom errors instead of revert strings
- Packed storage variables
- Immutable variables for constant values
- Optimized Merkle proof verification

**Scalability:**
- Factory pattern for easy deployment
- Support for large recipient lists via Merkle trees
- Incremental distribution capabilities
- Configurable distribution periods

## Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add or update tests as needed
5. Ensure all tests pass
6. Submit a Pull Request with a clear description of your changes

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.