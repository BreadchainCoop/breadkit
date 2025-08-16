// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {TestWrapper} from "./TestWrapper.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BreadKitFactory} from "../src/BreadKitFactory.sol";
import {SexyDaiYield} from "../src/token-types/SexyDaiYield.sol";
import {IBreadKitToken} from "../src/interfaces/IBreadKitToken.sol";
import {IWXDAI} from "../src/interfaces/IWXDAI.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BreadKitTest is TestWrapper {
    address constant wxDAI = 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d;
    address constant sxDAI = 0xaf204776c7245bF4147c2612BF6e5972Ee483701;
    BreadKitFactory public factory;
    IBreadKitToken public token;
    address public constant randomHolder = 0x23b4f73FB31e89B27De17f9c5DE2660cc1FB0CdF; // random multisig
    address public constant randomEOA = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        factory = new BreadKitFactory(address(this));

        /// @dev this is how we deploy and whitelist a new token type
        address impl = address(new SexyDaiYield(wxDAI, sxDAI));
        address beacon = address(new UpgradeableBeacon(impl, address(this)));
        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        /// @dev this is how we deploy a new token

        // encode initialization payload for given token type
        bytes memory payload = abi.encodeWithSelector(SexyDaiYield.initialize.selector, "TOKEN", "T", address(this));

        // deploy token
        token = IBreadKitToken(factory.createToken(address(beacon), payload, keccak256("random salt")));

        // deploy yield claimer
        address[] memory recipients = new address[](1);
        address claimer =
            factory.createDefaultYieldClaimer(address(token), recipients, 0, address(this), keccak256("random salt"));

        // set yield claimer
        token.setYieldClaimer(claimer);

        // burn 1 wei
        token.mint{value: 1}(0x0000000000000000000000000000000000000009);
    }

    function test_mint() public {
        uint256 supplyBefore = token.totalSupply();
        uint256 balBefore = token.balanceOf(address(this));
        uint256 contractBalBefore = IERC20(sxDAI).balanceOf(address(token));

        assertEq(supplyBefore, 1);
        assertEq(balBefore, 0);
        assertEq(contractBalBefore, 0);

        token.mint{value: 1 ether}(address(this));

        uint256 supplyAfter = token.totalSupply();
        uint256 balAfter = token.balanceOf(address(this));
        uint256 contractBalAfter = IERC20(sxDAI).balanceOf(address(token));

        assertEq(supplyAfter, supplyBefore + 1 ether);
        assertEq(balAfter, balBefore + 1 ether);
        assertGt(contractBalAfter, contractBalBefore);
        assertLt(contractBalAfter, supplyBefore + 1 ether);

        uint256 yieldBefore = token.yieldAccrued();
        assertEq(yieldBefore, 0);

        token.transfer(randomEOA, 0.5 ether);
        assertEq(token.balanceOf(address(this)), 0.5 ether);
        assertEq(token.balanceOf(randomEOA), 0.5 ether);

        IWXDAI(wxDAI).deposit{value: 1 ether}();

        IERC20(wxDAI).approve(address(token), 1 ether);
        token.mint(address(this), 1 ether);

        assertEq(token.balanceOf(address(this)), 1.5 ether);
    }
}
