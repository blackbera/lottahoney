#!/bin/bash
# SPDX-License-Identifier: MIT

## This script can be run after deploying the BerpsDeployer contract ##

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

# Deploy and initialize all contracts
printf "Running DeployAndInitialize...\n"
OUTPUT=$(ETH_FROM=$GOV forge script DeployAndInitialize --optimize --optimizer-runs 2000 --via-ir --private-key $GOV_PK --broadcast --rpc-url=$RPC_URL --legacy)
printf "$OUTPUT\n"  

# Call the Markets GlobalSettings
printf "\nRunning GlobalSettings...\n"
OUTPUT=$(ETH_FROM=$GOV forge script GlobalSettings --private-key $GOV_PK --broadcast --rpc-url=$RPC_URL --legacy)
printf "$OUTPUT\n"
