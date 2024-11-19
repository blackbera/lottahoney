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

printf "Adding BTCUSDCPair...\n"
OUTPUT=$(ETH_FROM=$GOV forge script BTCUSDCPair --private-key $GOV_PK --broadcast --rpc-url=$RPC_URL --legacy)
printf "$OUTPUT\n"

printf "\nAdding ETHUSDCPair...\n" 
OUTPUT=$(ETH_FROM=$GOV forge script ETHUSDCPair --private-key $GOV_PK --broadcast --rpc-url=$RPC_URL --legacy)
printf "$OUTPUT\n"

printf "\nAdding ATOMUSDCPair...\n"
OUTPUT=$(ETH_FROM=$GOV forge script ATOMUSDCPair --private-key $GOV_PK --broadcast --rpc-url=$RPC_URL --legacy)
printf "$OUTPUT\n"

printf "\nAdding TIAUSDCPair...\n"
OUTPUT=$(ETH_FROM=$GOV forge script TIAUSDCPair --private-key $GOV_PK --broadcast --rpc-url=$RPC_URL --legacy)
printf "$OUTPUT\n"
