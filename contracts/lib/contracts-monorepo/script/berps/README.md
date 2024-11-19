# Deploying the Berps Contracts

The scripts in this directory are used to deploy, initialize, and setup the Berps contracts with initial pairs and fees
on top of a Pyth oracle. The following directions provide the instructions to run the scripts in this directory.

## Directions

0. Copy the `.envrc.example` into a file named `.envrc` (can use `cp .envrc.example .envrc`) and fill in the values. For
   all following steps running a bash script, you can use the `--use-env` flag to set the values as environment
   variables instead of the `.envrc` file.
1. Run `deploy-berps-deployer.sh` to setup the deployment process.
2. Set the Berps system parameters in `Deploy.s.sol` and then run `deploy-contracts.sh` to atomically deploy and
   initialize each of the Berps contracts.
3. [Optional] Set paramers for initial markets and run `deploy-markets.sh` to add initial pairs & fees to the Berps
   contracts.
4. [Optional] Run `deposit-vault.sh` to deposit some $HONEY into the Berps liquidity vault, which can be used to power
   trades in the system.

### The contracts are up

Run `print-addresses.sh` to easily view the addresses of all the Berps contracts anytime after Step 2 is completed.
