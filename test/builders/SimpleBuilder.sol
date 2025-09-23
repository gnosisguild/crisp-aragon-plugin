// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {TestBase} from "../lib/TestBase.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {CrispVoting} from "../../src/CrispVoting.sol";
import {CrispVotingSetup} from "../../src/setup/CrispVotingSetup.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {ICrispVoting} from "../../src/ICrispVoting.sol";
import {GovernanceERC20} from "@aragon/token-voting-plugin/erc20/GovernanceERC20.sol";

contract SimpleBuilder is TestBase {
    address immutable DAO_BASE = address(new DAO());
    address immutable UPGRADEABLE_PLUGIN_BASE = address(new CrispVoting());

    // Parameters to override
    address daoOwner; // Used for testing purposes only
    address[] managers; // daoOwner will be used if eventually empty
    uint256 initialNumber = 1;

    GovernanceERC20 governanceERC20Base;

    constructor() {
        // Set the caller as the initial daoOwner
        // It can grant and revoke permissions freely for testing purposes
        withDaoOwner(msg.sender);
    }

    // Override methods
    function withDaoOwner(address _newOwner) public returns (SimpleBuilder) {
        daoOwner = _newOwner;
        return this;
    }

    /// @dev Creates a DAO with the given orchestration settings.
    /// @dev The setup is done on block/timestamp 0 and tests should be made on block/timestamp 1 or later.
    function build() public returns (DAO dao, CrispVoting plugin) {
        // Deploy the DAO with `daoOwner` as ROOT
        dao = DAO(
            payable(
                ProxyLib.deployUUPSProxy(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", daoOwner, address(0x0), ""))
                )
            )
        );

        address[] memory receivers = new address[](1);
        receivers[0] = address(msg.sender);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e18;
        governanceERC20Base = new GovernanceERC20(IDAO(address(dao)), "TESTTOKEN", "TT", GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts}));

        uint256[2] memory threshold = [uint256(2), uint256(3)];

        address crispProgramAddress = 0x4ed7c70F96B99c776995fB64377f0d4aB3B0e1C1;
        address enclaveAddress = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
        address filterAddress = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;

        bytes memory crispProgramParams = "0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000fc00100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000003fffffff000001";
        bytes memory computeProviderParams = "0x7b226e616d65223a225249534330222c22706172616c6c656c223a66616c73652c2262617463685f73697a65223a347d";

        ICrispVoting.PluginInitParams memory pluginInitParams = ICrispVoting.PluginInitParams({
            dao: dao,
            token: address(governanceERC20Base),
            enclave: enclaveAddress,
            filter: filterAddress,
            threshold: threshold,
            crispProgramAddress: crispProgramAddress,
            crispProgramParams: crispProgramParams,
            computeProviderParams: computeProviderParams
        });

        // Plugin
        plugin = CrispVoting(
            ProxyLib.deployUUPSProxy(
                address(UPGRADEABLE_PLUGIN_BASE), abi.encodeCall(CrispVoting.initialize, (pluginInitParams))
            )
        );

        vm.startPrank(daoOwner);

        // Grant plugin permissions
        if (managers.length > 0) {
            for (uint256 i = 0; i < managers.length; i++) {
                dao.grant(address(plugin), managers[i], plugin.MANAGER_PERMISSION_ID());
            }
        } else {
            // Set the daoOwner as the plugin manager if no managers are defined
            dao.grant(address(plugin), daoOwner, plugin.MANAGER_PERMISSION_ID());
        }

        vm.stopPrank();

        // Labels
        vm.label(address(dao), "DAO");
        vm.label(address(plugin), "CrispPlugin");

        // Moving forward to avoid collisions
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }
}
