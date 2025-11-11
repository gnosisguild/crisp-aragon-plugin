// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.29;

import {Action} from "@aragon/osx/core/dao/DAO.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {ProposalUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/ProposalUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ICrispVoting} from "./ICrispVoting.sol";
import {IEnclave} from "./IEnclave.sol";
import {IE3Program, E3} from "./IE3.sol";

/// @title My Upgradeable Plugin
/// @notice A plugin that exposes a permissioned function to store a number and a function that makes the DAO execute an action.
/// @dev In order to call setNumber() the caller needs to hold the MANAGER_PERMISSION
/// @dev In order for resetDaoMetadata() to work, the plugin needs to hold EXECUTE_PERMISSION_ID on the DAO
/// @notice This plugin is inspired by MACI's voting plugin - https://github.com/privacy-ethereum/maci-voting-plugin-aragon/blob/main/src/MaciVoting.sol
contract CrispVoting is PluginUUPSUpgradeable, ProposalUpgradeable, ICrispVoting {
    /// @notice used to cast uint256 to uint64 safely
    using SafeCastUpgradeable for uint256;
    /// @notice used to perform safe ERC20 operations
    using SafeERC20 for IERC20;

    /// @notice The manager permission id
    bytes32 public constant MANAGER_PERMISSION_ID = keccak256("MANAGER_PERMISSION");

    /// @notice The interface id for the Crisp Voting plugin
    bytes4 internal constant CRISP_VOTING_INTERFACE_ID = this.initialize.selector ^ this.minProposerVotingPower.selector
        ^ this.totalVotingPower.selector ^ this.getVotingToken.selector ^ this.minParticipation.selector
        ^ this.minDuration.selector ^ this.getProposal.selector;

    /// @notice The enclave contract reference
    IEnclave public enclave;

    /// @notice The token used to pay for Enclave fees
    IERC20 public enclaveFeeToken;

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
    /// @param _params The plugin initialization parameters
    function initialize(PluginInitParams calldata _params) external initializer {
        __PluginUUPSUpgradeable_init(_params.dao);

        if (_params.enclave == address(0)) {
            revert ZeroAddress();
        }
        enclave = IEnclave(_params.enclave);
        votingToken = IVotesUpgradeable(_params.token);
        enclaveFeeToken = IERC20(enclave.feeToken());
        threshold = _params.threshold;
        crispProgramAddress = _params.crispProgramAddress;
        crispProgramParams = _params.crispProgramParams;
        computeProviderParams = _params.computeProviderParams;
    }

    /// @notice Creates a new E3 request in Enclave
    /// @dev This is a wrapper around the createProposal function as we need it to be payable
    /// as there will be charges for the E3 request in Enclave.
    /// @param _metadata The metadata of the proposal
    /// @param _actions The actions that will be executed if the proposal passes
    /// @param _startDate The start date of the proposal
    /// @param _endDate The end date of the proposal
    /// @param _data The additional abi-encoded data to include more necessary fields
    /// This includes whether to allow failures, and the enclave request start window details
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
        (uint256 _allowFailureMap, uint256[2] memory _startWindow) = abi.decode(_data, (uint256, uint256[2]));

        bytes memory customParams = abi.encode(address(votingToken), votingSettings.minProposerVotingPower);

        // we need to move this to own scope to avoid stack too deep
        {
            IEnclave.E3RequestParams memory requestParams = IEnclave.E3RequestParams({
                threshold: threshold,
                startWindow: _startWindow,
                duration: _endDate - _startDate,
                e3Program: IE3Program(crispProgramAddress),
                e3ProgramParams: crispProgramParams,
                computeProviderParams: computeProviderParams,
                customParams: customParams
            });

            // calculate the fee
            uint256 fee = enclave.getE3Quote(requestParams);
            // take it from the caller
            enclaveFeeToken.safeTransferFrom(_msgSender(), address(this), fee);
            // approve the enclave contract to take the fee
            enclaveFeeToken.approve(address(enclave), fee);

            // send the request to Enclave
            (uint256 e3Id,) = enclave.request(requestParams);

            // temp variables to store the proposal data
            TallyResults memory tallyResults = TallyResults({yes: 0, no: 0});
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

        emit ProposalCreated(proposalId, _msgSender(), _startDate, _endDate, _metadata, _actions, _allowFailureMap);
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

    /// @notice Internal checks to determine whether a proposal can be executed or not
    /// @param _proposalId The ID of the proposal to be checked
    /// @return Returns `true` if the proposal can be executed, otherwise false
    function _canExecute(uint256 _proposalId) internal view returns (bool) {
        Proposal memory proposal = proposals[_proposalId];

        if (proposal.executed) {
            return false;
        }

        return proposal.tally.yes > proposal.tally.no;
    }

    /// @inheritdoc IProposal
    function execute(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];

        E3 memory e3 = enclave.getE3(proposal.e3Id);

        uint256 inputsCount = enclave.inputsCount(proposal.e3Id);

        // Decode the first u64 (8 bytes) in little endian format
        // This represents the sum of all encrypted votes (number of '1's = Option 2 votes)
        uint256 option2 = decodeLittleEndianU64(e3.plaintextOutput, 0);

        // Calculate Option 1 votes
        uint256 option1 = inputsCount - option2;

        // now store the tally
        proposal.tally.yes = option1;
        proposal.tally.no = option2;

        // check if we can execute it3
        if (!_canExecute(_proposalId)) {
            revert ProposalExecutionForbidden(_proposalId);
        }

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

    /// @notice Decodes a u64 from bytes in little endian format at a given offset
    /// @param data The bytes array
    /// @param offset The starting position to read from
    /// @return The decoded uint64 value
    function decodeLittleEndianU64(bytes memory data, uint256 offset) public pure returns (uint256) {
        require(data.length >= offset + 8, "Insufficient data");

        uint256 result = 0;

        // Read 8 bytes in little endian order
        for (uint8 i = 0; i < 8; i++) {
            result |= uint256(uint8(data[offset + i])) << (i * 8);
        }

        return result;
    }

    /// @notice Get the tally result
    /// @param _proposalId The id of the proposal
    /// @return The tally result
    function getTally(uint256 _proposalId) external view returns (TallyResults memory) {
        Proposal memory proposal = proposals[_proposalId];

        // if it's not executed then we wouldn't have saved the result
        if (!proposal.executed) {
            E3 memory e3 = enclave.getE3(proposal.e3Id);

            uint256 inputsCount = enclave.inputsCount(proposal.e3Id);

            // Decode the first u64 (8 bytes) in little endian format
            // This represents the sum of all encrypted votes (number of '1's = Option 2 votes)
            uint256 option2 = decodeLittleEndianU64(e3.plaintextOutput, 0);

            // Calculate Option 1 votes
            uint256 option1 = inputsCount - option2;

            return TallyResults({yes: option1, no: option2});
        }

        return proposals[_proposalId].tally;
    }

    /// @notice This empty reserved space is put in place to allow future versions to add new variables
    ///         without shifting down storage in the inheritance chain
    ///         (see [OpenZeppelin's guide about storage gaps](https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)).
    uint256[49] private __gap;
}
