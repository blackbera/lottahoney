For deploying Berps smart contract via the kurtosis package, fill up `values.yaml` and place it inside the kurtosis
package in `beacon-kit` at location `testing/forge-script/dependency/values.yaml`.

This is how the `forge-config.yaml` file should look like

```bash
deployment:
  repository: "github.com/berachain/contracts-monorepo"
  contracts_path: ""
  script_path: ""
  contract_name: ""
  dependency:
    type : "git"
    path: "script/berps/dependency/dependency.sh"
    values: "dependency/values.yaml"
  rpc_url: "RPC_URL"
  wallet:
    type: "private_key"
    value: "PRIVATE_KEY"
```
