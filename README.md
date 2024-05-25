# Original README

- [Original README](ORIGINAL_README.md)

# Panda Finance

- [Panda Finance draft](PandaFinance.md)

# Quick Start

1. bun install
2. anvil, start local chain environment
3. Test
   - forge test --match-path test/CryptoSwap.t.sol --fork-url http://localhost:8545 -vv
   - forge test --match-test test_settle --fork-url http://localhost:8545 -vv
   - forge test --match-test test_SettleCase --fork-url http://localhost:8545 -vv
   - forge test --match-contract CryptoSwapTestFork (should config API_KEY_ALCHEMY in env )
   - forge test --match-path test/CryptoSwap.t.sol --match-test test_openBatchSwap -vv
4. Deploy
   - forge script script/DeployMockContracts.sol --rpc-url sepolia --broadcast --verify -vvvv
   - forge script script/arb/DeployCryptoSwap.sol --rpc-url arbitrum --broadcast --verify --legacy

# Doing

1. DealEngine

   1. the rules
   2. check profit different scenarios
   3. add different notional. like 100,1000,
   4. supply 5\*notional

2. More, check https://github.com/sodexx7/BlockMagic_Swap/blob/equitySwapDraft/test/EquitySwap.t.sol#L184
