# Aragon OSx CRISP (Enclave) voting plugin 🚀

Welcome to CRISP voting plugin for Aragon OSx!

This plugin is designed to enable secure and private voting on Aragon OSx enabled DAOs.

Under the hood, the plugin uses CRISP on Enclave to provide private voting. Read more about CRISP and Enclave [here](https://enclave.gg).

## Deployment

To deploy the plugin, first configure the `.env` file with the correct values. Then, run the deployment script:

```sh
forge script script/DeploySimple.s.sol:CrispVotingScript --rpc-url <rpc-url> --broadcast --verify 
```