// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {TestBase} from "../lib/TestBase.sol";

import {Action} from "@aragon/osx/core/dao/DAO.sol";
import {SimpleBuilder} from "../builders/SimpleBuilder.sol";
import {ICrispVoting} from "../../src/ICrispVoting.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {CrispVoting} from "../../src/CrispVoting.sol";
import {IERC20Mint} from "../../src/IERC20Mint.sol";

contract MyPluginTestFork is TestBase {
    DAO dao;
    CrispVoting plugin;

    /// @notice these are the addresses when deploying on a local hardhat network
    address crispProgramAddress = 0x75b0f71D6fD5E6BB426f223534fA12e38854f69E;
    address enclaveAddress = 0xB8dbC3149719e018D23ad5F49Ab73228Ef521991;
    address enclaveFeeToken = 0xBcAAFcAD5eF365B05eEB24d49eCf7A1c597195e1;

    bytes crispProgramParams =
        "0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000fc00100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000003fffffff000001";
    bytes computeProviderParams =
        "0x7b226e616d65223a225249534330222c22706172616c6c656c223a66616c73652c2262617463685f73697a65223a347d";

    ICrispVoting.PluginInitParams pluginInitParams = ICrispVoting.PluginInitParams({
        dao: dao,
        token: address(0),
        enclave: enclaveAddress,
        threshold: [uint32(2), uint32(3)],
        crispProgramAddress: crispProgramAddress,
        crispProgramParams: crispProgramParams,
        computeProviderParams: computeProviderParams
    });

    function setUp() public {
        // Customize the Builder to feature more default values and overrides
        (dao, plugin) = new SimpleBuilder().build();
    }

    function test_CreateE3Request() external payable {
        address alice = makeAddr("alice");

        // Make alice the msg.sender for the next call
        vm.startPrank(alice);

        IERC20Mint(enclaveFeeToken).mint(alice, 10e6);
        IERC20Mint(enclaveFeeToken).approve(address(plugin), 10e6);

        // It Should create a new E3 request
        plugin.createProposal(
            bytes(""),
            new Action[](0),
            uint64(block.timestamp),
            uint64(block.timestamp + 100),
            abi.encode(uint256(0), [uint256(block.timestamp), uint256(block.timestamp + 500)], 2, 0, 0)
        );

        vm.stopPrank();
    }
}
