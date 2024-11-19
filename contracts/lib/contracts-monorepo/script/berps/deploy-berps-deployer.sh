#!/bin/bash
# SPDX-License-Identifier: MIT

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

printf "Setting Honey address: $HONEY in Deploy.s.sol\n"
if sed --version 2>&1 | grep -q GNU; then
    sed -i "s/address _honey = address([^)]*);/address _honey = address($HONEY);/g" Deploy.s.sol
else
    sed -i '' "s/address _honey = address([^)]*);/address _honey = address($HONEY);/g" Deploy.s.sol
fi

printf "Setting Pyth address: $PYTH in Deploy.s.sol\n"
if sed --version 2>&1 | grep -q GNU; then
    sed -i "s/address _pyth = address([^)]*);/address _pyth = address($PYTH);/g" Deploy.s.sol
else
    sed -i '' "s/address _pyth = address([^)]*);/address _pyth = address($PYTH);/g" Deploy.s.sol
fi

printf "Setting FeeCollector address: $FEE_COLLECTOR in Deploy.s.sol\n"
if sed --version 2>&1 | grep -q GNU; then
    sed -i "s/address _feeCollector = address([^)]*);/address _feeCollector = address($FEE_COLLECTOR);/g" Deploy.s.sol
else
    sed -i '' "s/address _feeCollector = address([^)]*);/address _feeCollector = address($FEE_COLLECTOR);/g" Deploy.s.sol
fi

# Setup deployment with the BerpsDeployer
printf "\nRunning SetupDeployment... \n"
OUTPUT=$(ETH_FROM=$GOV forge script SetupDeployment --optimize --optimizer-runs 2000 --via-ir --private-key=$GOV_PK --broadcast --rpc-url=$RPC_URL --legacy)
printf "$OUTPUT\n"  

# Extract contract address
CA=$(echo "$OUTPUT" | grep "BerpsDeployer deployed at:" | awk '{print $NF}')

printf "\nSetting DEPLOYER in the Addresses library to: $CA\n"
if sed --version 2>&1 | grep -q GNU; then
    sed -i "s/BerpsDeployer(address([^)]*));/BerpsDeployer(address($CA));/g" Libraries.sol
else
    sed -i '' "s/BerpsDeployer(address([^)]*));/BerpsDeployer(address($CA));/g" Libraries.sol
fi

printf "\nSetting DEPLOYER address in the scripts: $CA\n"
if sed --version 2>&1 | grep -q GNU; then
    sed -i "s/^DEPLOYER=.*/DEPLOYER=$CA/" deposit-vault.sh
    sed -i "s/^DEPLOYER=.*/DEPLOYER=$CA/" print-addresses.sh
else
    sed -i '' "s/^DEPLOYER=.*/DEPLOYER=$CA/" deposit-vault.sh
    sed -i '' "s/^DEPLOYER=.*/DEPLOYER=$CA/" print-addresses.sh
fi
