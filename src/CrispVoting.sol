// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {IDAO, Action} from "@aragon/osx/core/dao/DAO.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {IEnclave} from "@enclave-e3/contracts/contracts/interfaces/IEnclave.sol";
import {IE3Program} from "@enclave-e3/contracts/contracts/interfaces/IE3Program.sol";
import {ProposalUpgradeable} from
    "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/ProposalUpgradeable.sol";
import {IVotesUpgradeable} from
"@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IProposal} from
    "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {SafeCastUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import { ICrispVoting } from "./ICrispVoting.sol";

/// @title My Upgradeable Plugin
/// @notice A plugin that exposes a permissioned function to store a number and a function that makes the DAO execute an action.
/// @dev In order to call setNumber() the caller needs to hold the MANAGER_PERMISSION
/// @dev In order for resetDaoMetadata() to work, the plugin needs to hold EXECUTE_PERMISSION_ID on the DAO
/// @notice This plugin is inspired by MACI's voting plugin - https://github.com/privacy-ethereum/maci-voting-plugin-aragon/blob/main/src/MaciVoting.sol
contract CrispVoting is PluginUUPSUpgradeable, ProposalUpgradeable, ICrispVoting {
    /// @notice used to cast uint256 to uint64 safely 
    using SafeCastUpgradeable for uint256;

    /// @notice The manager permission id
    bytes32 public constant MANAGER_PERMISSION_ID = keccak256("MANAGER_PERMISSION");

    /// @notice The interface id for the Crisp Voting plugin
    bytes4 internal constant CRISP_VOTING_INTERFACE_ID = this.initialize.selector
        ^ this.minProposerVotingPower.selector ^ this.totalVotingPower.selector
        ^ this.getVotingToken.selector ^ this.minParticipation.selector ^ this.minDuration.selector
        ^ this.getProposal.selector;

    /// @notice The enclave contract reference
    IEnclave public enclave;

    /// @notice An
    /// [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes)
    /// compatible contract referencing the token being used for voting.
    IVotesUpgradeable private votingToken;

    /// @notice The voting settings
    VotingSettings private votingSettings;

    /// @notice A mapping between proposal IDs and proposal information.
    mapping(uint256 => Proposal) internal proposals;

    /// @notice The Enclave ciphernode filter contract
    address private filter;
    /// @notice The ciphernode threshold
    uint32[2] private threshold;
    /// @notice The start window for the computation
    uint256[2] private startWindow;
    /// @notice The address of the E3 Program
    address private crispProgramAddress;
    /// @notice The ABI encoded program parameters
    bytes private crispProgramParams;
    /// @notice The ABI encoded compute provider parameters
    bytes private computeProviderParams;

    /// @notice Disables the initializers on the implementation contract to prevent
    /// it from being left uninitialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the plugin
    function initialize(PluginInitParams calldata _params) external initializer {
        __PluginUUPSUpgradeable_init(_params.dao);

        if (_params.enclave == address(0)) {
            revert ZeroAddress();
        }
        enclave = IEnclave(_params.enclave);
        votingToken = IVotesUpgradeable(_params.token);
    }


    /// @notice Creates a new proposal, as well as a new E3 request in Enclave
    /// @param _metadata The metadata of the proposal
    /// @param _actions The actions that will be executed if the proposal passes
    /// @param _startDate The start date of the proposal
    /// @param _endDate The end date of the proposal
    /// @param _data The additional abi-encoded data to include more necessary fields
    /// @return proposalId The id of the proposal
    function createProposal(
        bytes memory _metadata, 
        Action[] memory _actions, 
        uint64 _startDate, 
        uint64 _endDate, 
        bytes memory _data
    ) external returns (uint256 proposalId) {
        /// @notice Create a deterministic proposal id
        proposalId = _createProposalId(keccak256(abi.encode(_actions, _metadata)));

        /// @notice Get the proposal storage variable
        Proposal storage proposal = proposals[proposalId];

        // move to own scope to avoid stack too deep
        {
            /// @notice Check if the proposal already exists first
            if (_proposalExists(proposalId)) {
                revert ProposalAlreadyExists(proposalId);
            }

            /// @notice Check if the sender has enough voting power
            uint256 _minProposerVotingPower = minProposerVotingPower();
            if (_minProposerVotingPower != 0) {
                if (votingToken.getVotes(_msgSender()) < _minProposerVotingPower) {
                    revert ProposalCreationForbidden(_msgSender());
                }
            }
        }

        /// @notice Decode the data
        (uint256 _allowFailureMap,,) = abi.decode(_data, (uint256, uint8, bool));

        IEnclave.E3RequestParams memory requestParams = IEnclave.E3RequestParams({
            filter: filter,
            threshold: threshold,
            startWindow: startWindow,
            duration: _endDate - _startDate,
            e3Program: IE3Program(crispProgramAddress),
            e3ProgramParams: crispProgramParams,
            computeProviderParams: computeProviderParams
        });


        // send the request to Enclave
        (uint256 e3Id, ) = enclave.request(requestParams);

        // temp variables to store the proposal data 
        TallyResults memory tallyResults = TallyResults({
            yes: 0,
            no: 0
        });

        // we need to move this to own scope to avoid stack too deep
        {
            ProposalParameters memory proposalParameters = ProposalParameters({
                startDate: _startDate,
                endDate: _endDate,
                snapshotBlock: block.number,
                minVotingPower: votingSettings.minProposerVotingPower
            });
    
            /// @notice Store the data 
            proposal.executed = false;
            proposal.tally = tallyResults;
            proposal.parameters = proposalParameters;
            proposal.allowFailureMap = _allowFailureMap;
            proposal.targetConfig = getTargetConfig();
            proposal.e3Id = e3Id;
    
            for (uint256 i = 0; i < _actions.length;) {
                proposal.actions.push(_actions[i]);
    
                unchecked {
                    ++i;
                }
            }
        }

        emit ProposalCreated(
            proposalId, _msgSender(), _startDate, _endDate, _metadata, _actions, _allowFailureMap
        );
        
    }


    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(PluginUUPSUpgradeable, ProposalUpgradeable)
        returns (bool)
    {
        return _interfaceId == CRISP_VOTING_INTERFACE_ID || super.supportsInterface(_interfaceId);
    }

    /// @inheritdoc ICrispVoting
    function getVotingToken() public view returns (IVotesUpgradeable) {
        return votingToken;
    }

    /// @inheritdoc ICrispVoting
    function minParticipation() public view returns (uint32) {
        return votingSettings.minParticipation;
    }

    /// @inheritdoc ICrispVoting
    function minDuration() public view returns (uint64) {
        return votingSettings.minDuration;
    }

    /// @notice Returns whether the proposal has succeeded or not.
    /// @param _proposalId The id of the proposal.
    /// @return Whether the proposal has succeeded or not.
    function hasSucceeded(uint256 _proposalId) external view returns (bool) {
        return proposals[_proposalId].executed;
    }

    /// @notice Returns the proposal data for a given proposal ID.
    /// @param _proposalId The ID of the proposal to retrieve.
    /// @return proposal_ The proposal data including execution status, parameters, tally results,
    /// actions, and other metadata.
    function getProposal(uint256 _proposalId) external view returns (Proposal memory proposal_) {
        proposal_ = proposals[_proposalId];
    }

    /// @inheritdoc ICrispVoting
    function minProposerVotingPower() public view returns (uint256) {
        return votingSettings.minProposerVotingPower;
    }

    /// @inheritdoc ICrispVoting
    function totalVotingPower(uint256 _blockNumber) public view returns (uint256) {
        return votingToken.getPastTotalSupply(_blockNumber);
    }

    /// @notice Validates and returns the proposal vote dates.
    /// @param _start The start date of the proposal vote. If 0, the current timestamp is used
    /// and the vote starts immediately.
    /// @param _end The end date of the proposal vote. If 0, `_start + minDuration` is used.
    /// @return startDate The validated start date of the proposal vote.
    /// @return endDate The validated end date of the proposal vote.
    function _validateProposalDates(uint64 _start, uint64 _end)
        internal
        view
        returns (uint64 startDate, uint64 endDate)
    {
        uint64 currentTimestamp = block.timestamp.toUint64();

        if (_start == 0) {
            startDate = currentTimestamp;
        } else {
            startDate = _start;

            if (startDate < currentTimestamp) {
                revert DateOutOfBounds({limit: currentTimestamp, actual: startDate});
            }
        }

        // Since `minDuration` is limited to 1 year, `startDate + minDuration` can only overflow if
        // the `startDate` is after `type(uint64).max - minDuration`. In this case, the proposal
        // creation will revert and another date can be picked.
        uint64 earliestEndDate = startDate + votingSettings.minDuration;

        if (_end == 0) {
            endDate = earliestEndDate;
        } else {
            endDate = _end;

            if (endDate < earliestEndDate) {
                revert DateOutOfBounds({limit: earliestEndDate, actual: endDate});
            }
        }
    }

    /// @notice Checks if proposal exists or not.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if proposal exists, otherwise false.
    function _proposalExists(uint256 _proposalId) private view returns (bool) {
        return proposals[_proposalId].parameters.snapshotBlock != 0;
    }

    /// @inheritdoc IProposal
    function canExecute(uint256 _proposalId) public view returns (bool) {
        if (!_proposalExists(_proposalId)) {
            revert NonexistentProposal(_proposalId);
        }

        return _canExecute(_proposalId);
    }

    // @todo unmock this
    /// @notice Internal checks to determine whether a proposal can be executed or not
    /// @param _proposalId The ID of the proposal to be checked
    /// @return Returns `true` if the proposal can be executed, otherwise false
    function _canExecute(uint256 _proposalId) internal view returns (bool) {
        Proposal memory proposal = proposals[_proposalId];

        if (proposal.executed) {
            return false;
        }

        return true;
    }

    /// @inheritdoc IProposal
    function execute(uint256 _proposalId) external {
        // sanity checks first
        if (!_canExecute(_proposalId)) {
            revert ProposalExecutionForbidden(_proposalId);
        }

        Proposal storage proposal = proposals[_proposalId];

        /// @notice we set the proposal as executed so it cannot be executed again 
        proposal.executed = true;

        // just execute it
        _execute(
            proposal.targetConfig.target,
            bytes32(_proposalId),
            proposal.actions,
            proposal.allowFailureMap,
            proposal.targetConfig.operation
        );

        emit ProposalExecuted(_proposalId);
    }

    function customProposalParamsABI() external pure returns (string memory) {
        return "(uint256 allowFailureMap, uint8 voteOption, bool tryEarlyExecution)";
    }


    /// @notice This empty reserved space is put in place to allow future versions to add new variables
    ///         without shifting down storage in the inheritance chain
    ///         (see [OpenZeppelin's guide about storage gaps](https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)).
    uint256[49] private __gap;
}
