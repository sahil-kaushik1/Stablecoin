// SPDX-License-Identifier: MIT
// Have our invariant aka properties

// invariants-
// total supply of dsc should be less than total value of calleateral
// getter view function shhoul never rever <- evergreen invariant

pragma solidity 0.8.20;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStablecoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract OpenInvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralisedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        console.log("Targeting contract:", address(dsce)); // Debug log
        handler = new Handler(dsce, dsc);
        targetContract((address(handler)));
        // console.log("done");
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getValueUSD(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getValueUSD(wbtc, totalWbtcDeposited);

        console.log("weth", wethValue);
        console.log("wbtc", wbtcValue);
        console.log("total supply", totalSupply);
        console.log("times mint called", handler.timemintiscalled());
        assert((wethValue + wbtcValue) >= totalSupply);
    }
}
