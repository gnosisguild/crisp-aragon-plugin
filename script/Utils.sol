// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Vm} from "forge-std/Test.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

import {GovernanceERC20} from "@aragon/token-voting-plugin/erc20/GovernanceERC20.sol";

import {ICrispVoting} from "../src/ICrispVoting.sol";
import {CrispVotingSetup} from "../src/setup/CrispVotingSetup.sol";

library Utils {
    // the canonical hevm cheat‑code address
    Vm public constant VM = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    struct CrispEnvVariables {
        address enclave;
        address registryFilter;
        address crispProgramAddress;
        ICrispVoting.VotingSettings votingSettings;
        IPlugin.TargetConfig targetConfig;
        uint256[2] threshold;
        bytes crispProgramParams;
        bytes computeProviderParams;
    }

    function readCrispEnv() public view returns (CrispEnvVariables memory crispEnvVariables) {
        IPlugin.TargetConfig memory defaultTargetConfig =
            IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call});

        crispEnvVariables.enclave = VM.envAddress("ENCLAVE_ADDRESS");
        crispEnvVariables.registryFilter = VM.envAddress("FILTER_ADDRESS");
        crispEnvVariables.crispProgramAddress = VM.envAddress("CRISP_PROGRAM_ADDRESS");
        crispEnvVariables.votingSettings = ICrispVoting.VotingSettings({
            minProposerVotingPower: VM.envUint("MINIMUM_PROPOSER_VOTING_POWER"),
            minDuration: uint64(VM.envUint("MINIMUM_DURATION")),
            minParticipation: uint32(VM.envUint("MINIMUM_PARTICIPATION"))
        });
        crispEnvVariables.targetConfig = defaultTargetConfig;
        crispEnvVariables.threshold[0] = VM.envUint("THRESHOLD_0");
        crispEnvVariables.threshold[1] = VM.envUint("THRESHOLD_1");
        crispEnvVariables.crispProgramParams = VM.envBytes("CRISP_PROGRAM_PARAMS");
        crispEnvVariables.computeProviderParams = VM.envBytes("COMPUTE_PROVIDER_PARAMS");
    }

    function getGovernanceTokenAndMintSettings()
        public
        returns (GovernanceERC20, CrispVotingSetup.TokenSettings memory, GovernanceERC20.MintSettings memory)
    {
        CrispVotingSetup.TokenSettings memory tokenSettings = CrispVotingSetup.TokenSettings({
            addr: address(0), // If set to `address(0)`, a new `GovernanceERC20` token is deployed
            name: VM.envString("TOKEN_NAME"),
            symbol: VM.envString("TOKEN_SYMBOL")
        });
        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: new address[](3), amounts: new uint256[](3)});

        address[] memory receivers = VM.envAddress("MINT_SETTINGS_RECEIVERS", ",");
        uint256 amount = VM.envUint("MINT_SETTINGS_AMOUNT");
        mintSettings.receivers = receivers;
        mintSettings.amounts = new uint256[](receivers.length);
        for (uint256 i = 0; i < receivers.length; i++) {
            mintSettings.amounts[i] = amount;
        }

        GovernanceERC20 governanceERC20Base =
            new GovernanceERC20(IDAO(address(0x0)), tokenSettings.name, tokenSettings.symbol, mintSettings);
        return (governanceERC20Base, tokenSettings, mintSettings);
    }
}
