// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {TestBase} from "./lib/TestBase.sol";

import {Action} from "@aragon/osx/core/dao/DAO.sol";
import {SimpleBuilder} from "./builders/SimpleBuilder.sol";
import {ICrispVoting} from "../src/ICrispVoting.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {CrispVoting} from "../src/CrispVoting.sol";

contract MyPluginTest is TestBase {
    DAO dao;
    CrispVoting plugin;

    /// @notice these are the addresses when deploying on a local hardhat network
    address crispProgramAddress = 0x4ed7c70F96B99c776995fB64377f0d4aB3B0e1C1;
    address enclaveAddress = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    address filterAddress = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;

    bytes crispProgramParams =
        "0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000fc00100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000003fffffff000001";
    bytes computeProviderParams =
        "0x7b226e616d65223a225249534330222c22706172616c6c656c223a66616c73652c2262617463685f73697a65223a347d";

    ICrispVoting.PluginInitParams pluginInitParams = ICrispVoting.PluginInitParams({
        dao: dao,
        token: address(0),
        enclave: enclaveAddress,
        filter: filterAddress,
        threshold: [uint32(2), uint32(3)],
        crispProgramAddress: crispProgramAddress,
        crispProgramParams: crispProgramParams,
        computeProviderParams: computeProviderParams
    });

    function setUp() public {
        // Customize the Builder to feature more default values and overrides
        (dao, plugin) = new SimpleBuilder().build();
    }

    function test_RevertWhen_CallingInitialize() external {
        // It Should revert
        vm.expectRevert("Initializable: contract is already initialized");
        plugin.initialize(pluginInitParams);
    }

    function test_WhenCallingDao() external view {
        // It Should return the right values
        assertEq(address(plugin.dao()), address(dao));
    }
}
