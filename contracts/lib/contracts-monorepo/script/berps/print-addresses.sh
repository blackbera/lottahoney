#!/bin/bash
# SPDX-License-Identifier: MIT

## This script can be run after deploying all contracts ##

# Initialize a variable to track whether to use the environment setup
USE_ENVRC=true

# Loop through all the arguments
for arg in "$@"
do
    case $arg in
        --use-env)
        USE_ENVRC=false
        shift # Remove --use-env from processing
        ;;
        *)
        # Unknown option
        ;;
    esac
done

# Conditionally source .envrc based on the flag
if [ "$USE_ENVRC" = true ]; then
    source .envrc
fi

# deployer address for the contracts (automatically filled in)
DEPLOYER=
IMPL_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc # ERC1967 Implementation Slot

printf "Berps Contracts\n\n"
printf "Deployer: \"$DEPLOYER\"\n\n"

ENTRYPOINT=$(cast call $DEPLOYER "entrypointProxy()(address)" --rpc-url=$RPC_URL)
echo "Entrypoint: \"$ENTRYPOINT\""
ENTRYPOINT_IMPL=$(cast storage $ENTRYPOINT $IMPL_SLOT --rpc-url=$RPC_URL)
echo "Entrypoint Impl: \"0x$(echo $ENTRYPOINT_IMPL | sed 's/^0x0*\([0-9a-fA-F]\{40\}\)/\1/')\""

ORDERS=$(cast call $DEPLOYER "ordersProxy()(address)" --rpc-url=$RPC_URL)
echo "Orders: \"$ORDERS\""
ORDERS_IMPL=$(cast storage $ORDERS $IMPL_SLOT --rpc-url=$RPC_URL)
echo "Orders Impl: \"0x$(echo $ORDERS_IMPL | sed 's/^0x0*\([0-9a-fA-F]\{40\}\)/\1/')\""

SETTLEMENT=$(cast call $DEPLOYER "settlementProxy()(address)" --rpc-url=$RPC_URL)
echo "Settlement: \"$SETTLEMENT\""
SETTLEMENT_IMPL=$(cast storage $SETTLEMENT $IMPL_SLOT --rpc-url=$RPC_URL)
echo "Settlement Impl: \"0x$(echo $SETTLEMENT_IMPL | sed 's/^0x0*\([0-9a-fA-F]\{40\}\)/\1/')\""

FEESMARKETS=$(cast call $DEPLOYER "feesMarketsProxy()(address)" --rpc-url=$RPC_URL)
echo "FeesMarkets: \"$FEESMARKETS\""
FEESMARKETS_IMPL=$(cast storage $FEESMARKETS $IMPL_SLOT --rpc-url=$RPC_URL)
echo "FeesMarkets Impl: \"0x$(echo $FEESMARKETS_IMPL | sed 's/^0x0*\([0-9a-fA-F]\{40\}\)/\1/')\""

VAULT=$(cast call $DEPLOYER "vaultProxy()(address)" --rpc-url=$RPC_URL)
echo "Vault: \"$VAULT\""
VAULT_IMPL=$(cast storage $VAULT $IMPL_SLOT --rpc-url=$RPC_URL)
echo "Vault Impl: \"0x$(echo $VAULT_IMPL | sed 's/^0x0*\([0-9a-fA-F]\{40\}\)/\1/')\""

FEESACCRUED=$(cast call $DEPLOYER "feesAccruedProxy()(address)" --rpc-url=$RPC_URL)
echo "FeesAccrued: \"$FEESACCRUED\""
FEESACCRUED_IMPL=$(cast storage $FEESACCRUED $IMPL_SLOT --rpc-url=$RPC_URL)
echo "FeesAccrued Impl: \"0x$(echo $FEESACCRUED_IMPL | sed 's/^0x0*\([0-9a-fA-F]\{40\}\)/\1/')\""

MARKETS=$(cast call $DEPLOYER "marketsProxy()(address)" --rpc-url=$RPC_URL)
echo "Markets: \"$MARKETS\""
MARKETS_IMPL=$(cast storage $MARKETS $IMPL_SLOT --rpc-url=$RPC_URL)
echo "Markets Impl: \"0x$(echo $MARKETS_IMPL | sed 's/^0x0*\([0-9a-fA-F]\{40\}\)/\1/')\""

REFERRALS=$(cast call $DEPLOYER "referralsProxy()(address)" --rpc-url=$RPC_URL)
echo "Referrals: \"$REFERRALS\""
REFERRALS_IMPL=$(cast storage $REFERRALS $IMPL_SLOT --rpc-url=$RPC_URL)
echo "Referrals Impl: \"0x$(echo $REFERRALS_IMPL | sed 's/^0x0*\([0-9a-fA-F]\{40\}\)/\1/')\""

SAFETYMODULE=$(cast call $DEPLOYER "vaultSafetyModuleProxy()(address)" --rpc-url=$RPC_URL)
echo "SafetyModule: \"$SAFETYMODULE\""
SAFETYMODULE_IMPL=$(cast storage $SAFETYMODULE $IMPL_SLOT --rpc-url=$RPC_URL)
echo "SafetyModule Impl: \"0x$(echo $SAFETYMODULE_IMPL | sed 's/^0x0*\([0-9a-fA-F]\{40\}\)/\1/')\""

PYTH=$(cast call $ENTRYPOINT "pyth()(address)" --rpc-url=$RPC_URL)
echo "Pyth: \"$PYTH\""
