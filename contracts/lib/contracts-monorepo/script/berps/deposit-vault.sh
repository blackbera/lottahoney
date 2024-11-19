#!/bin/bash
# SPDX-License-Identifier: MIT

## This script can be optionally run after deploying all contracts ##

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

# approve the bHoney vault to transfer (5billion) HONEY from depositor
printf "Approving the bHONEY vault to transfer (5billion) HONEY from depositor... \n"
VAULT=$(cast call $DEPLOYER "vaultProxy()(address)" --rpc-url=$RPC_URL)
OUTPUT=$(cast send $HONEY "approve(address,uint256)(bool)" $VAULT 5000000000ether --private-key $DEP_PK --rpc-url=$RPC_URL --legacy)
printf "$OUTPUT\n" 

# deposit 10 million $HONEY into the vault to begin
printf "\nDepositing 10 million HONEY into the vault to begin... \n"
OUTPUT=$(cast send $VAULT "deposit(uint256,address)(uint256)" 10000000ether $DEPOSITOR --private-key $DEP_PK --rpc-url=$RPC_URL --legacy)
printf "$OUTPUT\n" 
