# Universal Sniper

Switss-knife for Uniswap V2, V3 liquidity interaction strategies.

## Commands

1. Create low-cost vault contracts for multi-wallet strategies. (Commands.CREATE_VAULT)
2. You can bribe the `block.coinbase` for MEV strategies. (Commands.BRIBE_MEV)
3. Transfer tokens from the temporary vaults. (Commands.TRANSFER_FROM_VAULT)
4. Send a buy swap with Uniswap V2 pool. (Commands.BUY_V2)
5. Send a sell swap with Uniswap V2 pool. (Commands.SELL_V2)
6. Send a buy swap with Uniswap V3 pool. (Commands.BUY_V3)
7. Send a sell swap with Uniswap V3 pool. (Commands.SELL_V3)

## Install & Compile

1. `npm i`
2. `npx hardhat compile`

## Usage & Testing

You can find usage code snippets from the test files.

`npx hardhat test/sniper.ts`
