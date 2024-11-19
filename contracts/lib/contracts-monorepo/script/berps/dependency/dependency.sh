#!/bin/sh
# SPDX-License-Identifier: MIT

apk update && apk add --no-cache nodejs npm

npm --version
npm install -g bun

bun --version

bun install
echo "Bun installation complete!"

echo "Installing dependencies for Berps"

cd /app/contracts && sh script/berps/dependency/populate-envrc.sh

cd /app/contracts && forge build

# We need to run the following scripts in order to deploy the contracts
cd script/berps
sh deploy-berps-deployer.sh >> output.json
sh deploy-contracts.sh >> output.json

cp output.json /app/contracts/output.json
