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

### PredyPool.sol

Short ETH(Base token) flow.

```mermaid
sequenceDiagram
autonumber
  Market->>PredyPool: trade(tradeParams, settlementData)
  activate PredyPool
  PredyPool->>UniswapSettlement: predySettlementCallback(data, baseAmount)
  activate UniswapSettlement
  UniswapSettlement->>PredyPool: take(to, baseAmount)
  activate PredyPool
  PredyPool-->>UniswapSettlement: 
  deactivate PredyPool
  UniswapSettlement ->> SwapRouter: exactInput(baseAmount)
  SwapRouter -->> UniswapSettlement: quoteAmountOut
  UniswapSettlement ->> USDC: transfer(to=PredyPool, quoteAmountOut)
  USDC -->> UniswapSettlement: 
  UniswapSettlement-->>PredyPool: 
  deactivate UniswapSettlement
  PredyPool->>Market: predyTradeAfterCallback(tradeParams, tradeResult)
  activate Market
  Market-->>PredyPool: 
  deactivate Market
  PredyPool-->>Market: 
  deactivate PredyPool
```

### PerpMarket.sol

Perp market & limit order flow.

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

Spot trading & market order flow.

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
  SpotMarket ->> Settlement: predySettlementCallback(settlementData, baseTokenAmount)
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
