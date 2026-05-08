# Token Distributor

This repository provides comprehensive documentation and example smart contracts for TokenDistributor - a sophisticated token distribution platform built with security, gas efficiency, and scalability in mind. The platform supports both ERC20 tokens and native tokens (ETH) for flexible distribution campaigns.

## Project Structure

```
contracts/
├── DistributorFactory.sol    # Factory contract for creating token distributors
└── TokenDistributor.sol      # Core distribution contract with Merkle tree verification

test/
├── DistributorTest.t.sol     # Comprehensive unit and integration tests
├── DistributorComplexTest.t.sol  # Advanced tests with real Merkle tree verification
└── NativeTokenDistributorTest.t.sol  # Native token distribution tests
```

## Smart Contracts

### DistributorFactory.sol

A factory contract that allows anyone to create token distribution campaigns for both ERC20 and native tokens.

**Key Features:**
- **Factory Pattern**: Creates new `TokenDistributor` instances
- **Dual Token Support**: Supports both ERC20 tokens and native tokens (ETH)
- **Token Transfer**: Automatically transfers tokens from creator to distributor contract
- **Access Control**: Validates token address, operator address, and total amount
- **Event Tracking**: Emits `DistributorCreated` events for transparency

**Core Functions:**
- `createDistributor(address token, address operator, uint256 initialTotalAmount)` - Creates a new distributor contract
  - For ERC20 tokens: Requires sufficient balance and approval
  - For native tokens: Requires sending ETH with the transaction

**Security Features:**
- Custom errors for gas-efficient error handling
- Input validation for zero addresses and amounts
- SafeERC20 for secure token transfers
- Native token validation and transfer protection

### TokenDistributor.sol

A Merkle tree-based token distribution contract with advanced features supporting both ERC20 and native tokens.

**Key Features:**
- **Merkle Tree Verification**: Efficient distribution to large recipient lists
- **Dual Token Support**: Supports both ERC20 tokens and native tokens (ETH)
- **Flexible Time-based Distribution**: Configurable start times with custom duration (1 second to 365 days)
- **Multi-round Distribution**: Support for multiple distribution rounds using remaining tokens
- **Incremental Claims**: Support for partial claiming and distribution updates
- **Access Control**: Separate owner and operator roles
- **Reentrancy Protection**: Uses OpenZeppelin's ReentrancyGuard

**Core Functions:**
- `setTime(uint256 _startTime, uint256 _duration)` - Set distribution start time and duration (operator only)
- `setMerkleRoot(bytes32 _merkleRoot)` - Set Merkle root for claim validation (operator only)
- `claim(uint256 maxAmount, bytes32[] calldata proof)` - Claim tokens using Merkle proof
- `withdraw()` - Withdraw remaining tokens after distribution ends or before it starts (owner only)

**Security Features:**
- Checks-Effects-Interactions pattern
- Custom errors for gas efficiency
- Time validation (max 90 days future start time, max 365 days duration)
- Distribution period protection (cannot modify time during active distribution)
- Merkle proof verification using OpenZeppelin's library
- Immutable variables for critical parameters
- Native token handling with proper validation

**Constants:**
- `MAX_DURATION = 365 days` - Maximum distribution period length
- `MAX_START_TIME = 90 days` - Maximum future start time
- `ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` - Native token identifier

## Test Suite

### DistributorTest.t.sol

Comprehensive test suite covering all contract functionality for both ERC20 and native tokens.

**Test Categories:**

**Factory Tests:**
- Successful distributor creation for ERC20 tokens
- Successful distributor creation for native tokens
- Input validation (invalid token, operator, amounts)
- Insufficient allowance handling for ERC20 tokens
- Native token amount validation

**Distributor Core Tests:**
- Constructor parameter validation
- Time setting functionality with custom duration and restrictions
- Duration validation (testing MAX_DURATION limits)
- Multi-round distribution capabilities
- Merkle root setting and updates
- Claim functionality with various scenarios for both token types
- Withdrawal functionality and access control

**Integration Tests:**
- Complete workflow from creation to withdrawal
- Multiple user scenarios with different distribution durations
- Multi-round distribution workflows using remaining tokens
- Partial claiming functionality
- Native token distribution workflows

**Edge Cases:**
- Invalid proofs and amounts
- Double claiming prevention
- Time-based restrictions and duration limits
- Distribution period protection (cannot modify during active distribution)
- Access control validation
- Native token edge cases

### DistributorComplexTest.t.sol

Advanced test suite with real Merkle tree implementation for ERC20 tokens.

**Key Features:**
- **Real Merkle Tree**: Implements actual Merkle tree generation and proof verification
- **Multi-user Scenarios**: Tests with three users (Alice, Bob, Charlie) with different amounts
- **Complex Workflows**: End-to-end testing with realistic distribution scenarios
- **Multi-round Distribution**: Tests multiple distribution rounds using remaining tokens
- **Duration Testing**: Comprehensive testing of InvalidDuration error conditions
- **Time Restriction Testing**: Validates distribution period protection logic
- **Proof Validation**: Tests both valid and invalid Merkle proofs
- **Partial Claiming**: Demonstrates incremental distribution capabilities

### NativeTokenDistributorTest.t.sol

Specialized test suite for native token distribution functionality.

**Key Features:**
- **Native Token Workflows**: Complete testing of ETH distribution scenarios
- **Factory Integration**: Tests native token distributor creation through factory
- **Claim Testing**: Native token claiming with Merkle proof verification
- **Withdrawal Testing**: Owner withdrawal of remaining native tokens
- **Edge Cases**: Native token specific edge cases and error handling

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
- Native token handling with proper validation

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
- Support for both ERC20 and native tokens

**Flexibility:**
- Dual token support (ERC20 and native tokens)
- Configurable distribution periods (1 second to 365 days)
- Multi-round distribution capabilities
- Incremental claiming support
- Operator-controlled distribution parameters
- Post-distribution token reuse for new campaigns

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