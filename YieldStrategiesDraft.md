## YieldStrategies

1. There are two type yield strategys, one is aggregator like yearn, another is primitive defi, like lido.

2. For simplicity, no matter which type. just directly call the deposit function, then transfer the token to
   SwapContract itself.

3. Integration mode.

   - Apply Delegated Deposit as https://docs.yearn.finance/partners/integration_guide

4. To make the YieldStrategies work, should test in fork mode

5. As there are more logics behind YieldStrategies, now only supply yearn. Because the amount of usdc per share are
   changing, should maintain the relationships. Now just return corresponding's value.
   - yvUSDC(0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE),
   - API doc: https://docs.yearn.fi/vaults/smart-contracts/vault#withdraw
   - code: https://github.com/yearn/yearn-vaults/blob/97ca1b2e4fcf20f4be0ff456dabd020bfeb6697b/contracts/Vault.vy#L1033
