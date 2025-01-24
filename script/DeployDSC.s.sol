pragma solidity ^0.8.20;

import {Script} from "lib/forge-std/src/Script.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAdddress;
    address[] public priceFeedAddress;

    function run()
        external
        returns (DecentralisedStableCoin, DSCEngine, HelperConfig)
    {
        HelperConfig helperconfig = new HelperConfig();
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = helperconfig.activeNetworkConfig();

        tokenAdddress = [weth, wbtc];
        priceFeedAddress = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        vm.startBroadcast();
        DecentralisedStableCoin dsc = new DecentralisedStableCoin();
        DSCEngine engine = new DSCEngine(
            tokenAdddress,
            priceFeedAddress,
            address(dsc)
        );
        dsc.transferOwnership(address(engine));

        vm.stopBroadcast();
        return (dsc, engine, helperconfig);
    }
}
