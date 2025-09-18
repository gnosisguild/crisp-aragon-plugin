// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVotesUpgradeable} from
"@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

/// @notice Interface for the Crisp Voting plugin
interface ICrispVoting {
    /// @notice Thrown if the address is zero.
    error ZeroAddress();
    /// @notice Thrown if the proposal with same actions and metadata already exists.
    /// @param proposalId The id of the proposal.
    error ProposalAlreadyExists(uint256 proposalId);
    /// @notice Thrown when a sender is not allowed to create a proposal.
    /// @param _address The sender address.
    error ProposalCreationForbidden(address _address);
    /// @notice Thrown if the proposal execution is forbidden.
    /// @param proposalId The ID of the proposal.
    error ProposalExecutionForbidden(uint256 proposalId);
    /// @notice Thrown when a proposal doesn't exist.
    /// @param proposalId The ID of the proposal which doesn't exist.
    error NonexistentProposal(uint256 proposalId);
    /// @notice Thrown when the caller doesn't have enough voting power.
    error NoVotingPower();
    /// @notice Thrown when the proposal is not in the voting period.
    /// @param limit The bound limit (start or end date).
    /// @param actual The actual time.
    error DateOutOfBounds(uint64 limit, uint64 actual);

    /// @notice A struct for the voting settings.
    /// @param minProposerVotingPower The minimum voting power needed to propose a vote.
    /// @param minParticipation The minimum participation needed to vote.
    /// @param minDuration The minimum duration of the vote.
    struct VotingSettings {
        uint256 minProposerVotingPower;
        uint32 minParticipation;
        uint64 minDuration;
    }

    /// @notice A struct for the results of the voting. We read from the Enclave contract and
    /// store the results here.
    /// @notice For now we do not support abstain votes so we can reduce the number of greco proofs to be generated. 
    /// Either way, in most governance proposals, abstain votes do not affect the outcome.
    /// @param yes The number of votes for the "yes" option.
    /// @param no The number of votes for the "no" option.
    struct TallyResults {
        uint256 yes;
        uint256 no;
    }

    /// @notice A struct for the proposal parameters at the time of proposal creation.
    /// @param startDate The start date of the proposal vote.
    /// @param endDate The end date of the proposal vote.
    /// @param snapshotBlock The number of the block prior to the proposal creation.
    /// @param minVotingPower The minimum voting power needed.
    struct ProposalParameters {
        uint64 startDate;
        uint64 endDate;
        uint256 snapshotBlock;
        uint256 minVotingPower;
    }

    /// @notice The parameters for initializing the plugin
    /// @param dao The DAO contract address
    /// @param token The token contract address
    /// @param enclave The enclave contract address
    /// @param filter The address of the pool of nodes from which to select the committee.
    /// @param threshold The M/N threshold for the committee.
    /// @param startWindow The start window for the computation.
    /// @param e3Program The address of the E3 Program.
    /// @param e3ProgramParams The ABI encoded computation parameters.
    struct PluginInitParams {
        IDAO dao;
        address token;
        address enclave;
        address filter;
        uint256[2] threshold;
        uint256[2] startWindow;
        address crispProgramAddress;
        bytes crispProgramParams;
        bytes computeProviderParams;
    }


    /// @notice A struct for proposal-related information.
    /// @param executed Whether the proposal is executed or not.
    /// @param parameters The proposal parameters at the time of the proposal creation.
    /// @param actions The actions to be executed when the proposal passes.
    /// @param allowFailureMap A bitmap allowing the proposal to succeed, even if individual
    /// actions might revert. If the bit at index `i` is 1, the proposal succeeds even if the `i`th
    /// action reverts. A failure map value of 0 requires every action to not revert.
    /// @param targetConfig Configuration for the execution target, specifying the target address
    /// and operation type (either `Call` or `DelegateCall`). Defined by `TargetConfig` in the
    /// `IPlugin` interface,
    ///     part of the `osx-commons-contracts` package, added in build 3.
    /// @param e3Id The ID of the E3 request ID 
    struct Proposal {
        bool executed;
        ProposalParameters parameters;
        TallyResults tally;
        Action[] actions;
        uint256 allowFailureMap;
        IPlugin.TargetConfig targetConfig;
        uint256 e3Id;
    }

    /// @notice Returns the minimum voting power needed to propose a vote.
    /// @return The minimum voting power needed to propose a vote.
    function minProposerVotingPower() external view returns (uint256);

    /// @notice Returns the total voting power of the DAO at a given block number.
    /// @param _blockNumber The block number to get the total voting power at.
    /// @return The total voting power of the DAO at the given block number.
    function totalVotingPower(uint256 _blockNumber) external view returns (uint256);

    /// @notice Returns the voting token interface.
    /// @return The voting token interface.
    function getVotingToken() external view returns (IVotesUpgradeable);

    /// @notice Returns the minimum participation needed to vote.
    /// @return The minimum participation needed to vote.
    function minParticipation() external view returns (uint32);

    /// @notice Returns the minimum duration of the vote.
    /// @return The minimum duration of the vote.
    function minDuration() external view returns (uint64);

    /// @notice Returns the proposal data for a given proposal ID.
    /// @param _proposalId The id of the proposal.
    /// @return The proposal data.
    function getProposal(uint256 _proposalId) external view returns (Proposal memory);
}
