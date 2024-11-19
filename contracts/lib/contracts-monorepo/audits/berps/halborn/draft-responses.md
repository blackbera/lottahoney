# Draft Report Responses

07/05/2024

## 7.1 (HAL-04) INCONSISTENT REVERTS DUE TO INSUFFICIENT PYTH UPDATE FEE HANDLING

This is something we have already handled. There is a function `refundValue()` in the Entrypoint contract to return any overspent funds. Also it is not possible to refund overspent in the same call to `getPrice` as this will break the multicall logic in `PayableMulticall`. Hence it makes sense for users to do a multicall for trading operations with the `refundValue()` call being the last of the calls.

## 7.2 (HAL-05) MISSING IMPLEMENTATION OF FEE TRANSFER TO POL SYSTEM

This has been addressed in later versions past `berps-v0.1.5`. In the latest version of the [Vault](https://github.com/berachain/contracts-monorepo/blob/main/src/berps/core/v0/Vault.sol) there is a [VaultSafetyModule](https://github.com/berachain/contracts-monorepo/blob/main/src/berps/core/v0/VaultSafetyModule.sol) that handles the fee distribution to the PoL system.

## 7.3 (HAL-10) HARDCODED HONEY PRICE ENABLES DEVASTATING ARBITRAGE ATTACKS AND MEV EXPLOITATION

This is correct, as soon as we have a oracle price for HONEY (on Pyth), we will replace that. This is a hard prerequisite to deploy the Berps system. Issue created for reference [here](https://github.com/berachain/contracts-monorepo/issues/345).

## 7.4 (HAL-01) ISSUE IN NOTCONTRACT MODIFIER DUE TO FUTURE EVM CHANGES

This one is good to monitor. Switching to OZ's `isContract` function is not a huge lift. Issue created [here](https://github.com/berachain/contracts-monorepo/issues/346).

## 7.5 (HAL-02) MISSING __UUPSUPGRADEABLE_INIT() IN THE CONTRACTS

Good to know, will address this in the next upgrade. Issue created [here](https://github.com/berachain/contracts-monorepo/issues/347).


## 7.6 (HAL-07) LACK OF STORAGE GAP IN UPGRADEABLE CONTRACTS

Good point! Would be good add to all upgradeable contracts. Issue created [here](https://github.com/berachain/contracts-monorepo/issues/348).

## 7.7 (HAL-08) INCOMPLETE NATSPEC DOCUMENTATION AND TEST COVERAGE

Ongoing work to improve upon. Issue created [here](https://github.com/berachain/contracts-monorepo/issues/349).

## 7.8 (HAL-03) UNLOCKED PRAGMA

Good to know, will try to standardize across all contracts. Issue created [here](https://github.com/berachain/contracts-monorepo/issues/350).

## 7.9 (HAL-06) INCOMPATIBILITY RISK FOR EVM VERSIONS IN DIFFERENT CHAINS

We use the `TSTORE` and `TLOAD` opcodes in the PayableMulticall contract, so this will be important to ensure.

## 7.10 (HAL-09) USE OWNABLE2STEP INSTEAD OF OWNABLE

Good point, created issue [here](https://github.com/berachain/contracts-monorepo/issues/351).

## 7.11 (HAL-11) INCOMPLETE CANCELREASON CHECK IN EXECUTELIMITOPENORDERCALLBACK

This case is now handled in the latest version of [Settlement](https://github.com/berachain/contracts-monorepo/blob/main/src/berps/core/v0/Settlement.sol).
