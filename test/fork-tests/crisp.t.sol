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
    address crispProgramAddress = 0x0b75A4d93c686103a903091a91C869aD9ad9CB7B;
    address enclaveAddress = 0x95bC90fcb37684bfbAA3ffA2CbF4067fA404c4AA;
    address enclaveFeeToken = 0x80C5504A6704359C40B88777b1639096d3453804;

    bytes crispProgramParams =
        "0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000064000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000ffffee0010000000000000000000000000000000000000000000000000000000ffffc400100000000000000000000000000000000000000000000000000000000000000013300000000000000000000000000000000000000000000000000000000000000";
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
            abi.encode(uint256(0), 2, 0, 0)
        );

        vm.stopPrank();
    }
}
