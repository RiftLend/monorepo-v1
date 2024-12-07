# Multichain Flashloans

## Overview

Flash loans allow you to borrow any available amount of assets from the lending pool without providing any collateral. In our multichain implementation, flash loans are coordinated across chains but executed and repaid atomically within each individual chain. This enables advanced DeFi operations across the superchain while maintaining security and efficiency.

## Key Features

- Borrow multiple assets across multiple chains in a coordinated manner
- Each flash loan is atomic within its respective chain
- 0.09% flash loan fee (9 basis points)
- Enhanced transparency through cross-chain event monitoring
- Option to convert to a collateralized loan if unable to repay within transaction

## Architecture

### Cross-Chain Coordination

1. User initiates flash loan request specifying target chains
2. Cross-chain event is emitted and picked up by relayer
3. Relayer dispatches flash loan requests to respective chains
4. Each chain executes flash loan locally and atomically
5. Repayment must occur within same transaction on each chain

### Security Benefits

- Increased transparency compared to traditional flash loans by:
  - Smart contracts can have monitoring setup across chains.
  - Protection against private mempool exploitation because emits are public and protocols can setup monitoring for this.
- Local chain atomicity ensures proper repayment

## How to Use

### 1. Create a Flash Loan Receiver Contract

First, implement the IFlashLoanReceiver interface in your contract:

```solidity
import {IFlashLoanReceiver} from "./interfaces/IFlashLoanReceiver.sol";

contract MyFlashLoanReceiver is IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // Your flash loan logic here

        // Approve repayment
        for(uint i = 0; i < assets.length; i++) {
            uint amountOwed = amounts[i] + premiums[i];
            IERC20(assets[i]).approve(msg.sender, amountOwed);
        }

        return true;
    }
}
```

### 2. Initiate the Flash Loan

Call initiateFlashLoan() on the LendingPool contract:

```solidity
function initiateFlashLoan(
    uint256[] calldata chainIds,          // Target chain IDs
    address receiverAddress,              // Your flash loan receiver contract
    address[][] calldata assets,          // Assets to borrow per chain
    uint256[][] calldata amounts,         // Amounts to borrow per chain
    uint256[][] calldata modes,           // Repayment modes per chain
    address onBehalfOf,                   // Address that will receive debt if loan isn't repaid
    bytes[] calldata params,              // Custom params to pass to receiver
    uint16[] calldata referralCode        // Referral code (0 if none)
)
```

### Repayment Modes

For each borrowed asset, specify the repayment mode:

- 0: Must repay in same transaction or revert
- 1: Convert to stable rate loan if not repaid
- 2: Convert to variable rate loan if not repaid

### Example Usage

```solidity
// Flash loan parameters for multiple chains
uint256[] memory chainIds = new uint256[](2);
chainIds[0] = 1; // Ethereum mainnet
chainIds[1] = 10; // OP mainnet

address[][] memory assets = new address[][](2);
// Assets for chain 1
assets[0] = new address[](1);
assets[0][0] = ETH_ADDRESS;
// Assets for chain 2
assets[1] = new address[](1);
assets[1][0] = USDC_ADDRESS;

uint256[][] memory amounts = new uint256[][](2);
// Amounts for chain 1
amounts[0] = new uint256[](1);
amounts[0][0] = 1000 * 1e18; // 1000 ETH
// Amounts for chain 2
amounts[1] = new uint256[](1);
amounts[1][0] = 1000000 * 1e6; // 1M USDC

uint256[][] memory modes = new uint256[][](2);
modes[0] = new uint256[](1);
modes[0][0] = 0; // Must repay
modes[1] = new uint256[](1);
modes[1][0] = 0; // Must repay

bytes[] memory params = new bytes[](2);
params[0] = ""; // Optional parameters for chain 1
params[1] = ""; // Optional parameters for chain 2

uint16[] memory referralCode = new uint16[](2);
referralCode[0] = 0;
referralCode[1] = 0;

// Execute flash loan
lendingPool.initiateFlashLoan(
    chainIds,
    receiverAddress,
    assets,
    amounts,
    modes,
    msg.sender,
    params,
    referralCode
);
```

## Important Notes

1. Flash loans are not cross-chain atomic, but rather atomic within each individual chain
2. The initiating chain acts as a coordinator for the flash loan requests
3. Each borrowed asset must be repaid on its respective chain
4. No upfront collateral is required - fees are paid only upon successful execution
5. Cross-chain coordination may introduce additional latency
6. Asset availability must be considered for each target chain
