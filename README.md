predyx
=====

![](https://github.com/predyprotocol/predyx/workflows/test/badge.svg)

## Overview

TBD

## Development

```
# Installing dependencies
forge install

# Testing
forge test
```


## Architecture

This project centers around 1 key smart contract and three types of smart contracts: PredyPool, Settlement, Market, and Order Validator.
The Settlement contract defines how to swap tokens, while the Market and Order Validator contracts define financial products and order types.
Markets can leverage positions by utilizing PredyPool for token lending and borrowing. 

This architecture is very scalable. For example, developers can create new futures exchanges with minimal code. Specifically, they gain leverage by connecting to PredyPool. By leveraging existing settlement contracts, they can access many liquidity sources and support multiple order types through order validators.

### PredyPool.sol

Short ETH(Base token) flow.

```mermaid
sequenceDiagram
autonumber
  Market->>PredyPool: trade(tradeParams, settlementData)
  activate PredyPool
  PredyPool->>Market: predySettlementCallback(data, baseAmount)
  activate Market
  Market->>PredyPool: take(to, baseAmount)
  activate PredyPool
  PredyPool-->>Market: 
  deactivate PredyPool
  Market->>UniswapSettlement: swapExactIn(data, baseAmount)
  activate UniswapSettlement
  UniswapSettlement ->> SwapRouter: exactInput(baseAmount)
  SwapRouter -->> UniswapSettlement: quoteAmountOut
  UniswapSettlement ->> USDC: transfer(to=PredyPool, quoteAmountOut)
  USDC -->> UniswapSettlement: 
  UniswapSettlement-->>Market: 
  deactivate UniswapSettlement
  Market -->> PredyPool: 
  deactivate Market
  PredyPool->>Market: predyTradeAfterCallback(tradeParams, tradeResult)
  activate Market
  Market-->>PredyPool: 
  deactivate Market
  PredyPool-->>Market: 
  deactivate PredyPool
```

### PerpMarket.sol

Limit order flow of PerpMarket.

```mermaid
sequenceDiagram
autonumber
  actor Trader
  actor Filler
  Trader->>Filler: eip712 signedOrder
  Filler->>PerpMarket: executeOrder(signedOrder, settlementData)
  activate PerpMarket
  PerpMarket->>Permit2: permitWitnessTransferFrom
  Permit2-->>PerpMarket: 
  PerpMarket->>PredyPool: trade(tradeParams, settlementData)
  activate PredyPool
  PredyPool-->>PerpMarket: returns tradeResult
  deactivate PredyPool
  PerpMarket->>LimitOrderValidator: validate(tradeAmount, tradeAmountSqrt, tradeResult)
  activate LimitOrderValidator
  LimitOrderValidator-->>PerpMarket: 
  deactivate LimitOrderValidator
  PerpMarket-->>Filler: tradeResult
  deactivate PerpMarket
  Filler-->>Trader: 
```

### SpotMarket.sol

Market order flow of SpotMarket.

```mermaid
sequenceDiagram
autonumber
  actor Trader
  actor Filler
  Trader->>Filler: eip712 signedOrder
  Filler ->> SpotMarket: executeOrder(signedOrder, settlementData)
  activate SpotMarket
  SpotMarket ->> Permit2: permitWitnessTransferFrom
  activate Permit2
  Permit2 -->> SpotMarket: 
  deactivate Permit2
  SpotMarket ->> Settlement: swapExactIn(settlementData, baseTokenAmount)
  activate Settlement
  Settlement -->> SpotMarket: 
  deactivate Settlement
  SpotMarket ->> DutchOrderValidator: validate(baseTradeAmount, quoteTokenAmount, validationData)
  activate DutchOrderValidator
  DutchOrderValidator -->> SpotMarket: 
  deactivate DutchOrderValidator
  SpotMarket -->> Filler: 
  deactivate SpotMarket
  Filler-->>Trader: 
```
