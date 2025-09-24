# Aragon OSx CRISP (Enclave) voting plugin 🚀

Welcome to CRISP voting plugin for Aragon OSx!

This plugin is designed to enable secure and private voting on Aragon OSx enabled DAOs.

Under the hood, the plugin uses CRISP on Enclave to provide private voting. Read more about CRISP and Enclave [here](https://enclave.gg).

## Deployment

To deploy the plugin, first configure the `.env` file with the correct values. Then, run the deployment script:

```sh
forge script script/DeploySimple.s.sol:CrispVotingScript --rpc-url <rpc-url> --broadcast --verify
```

## Test

Test with a local fork of Enclave

1. Clone Enclave
2. Setup the project
   - `pnpm install && pnpm build`
3. Setup CRISP
   - `cd examples/CRISP`
   - `pnpm dev:up`
4. Run the tests
   - `pnpm test:fork`
