// Handler is going to narrow down how we call funcitons
// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;
import {Test, console} from "lib/forge-std/src/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStablecoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "lib/chainlink-brownie-contracts/contracts/src/v0.6/tests/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralisedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timemintiscalled;
    address[] public userwithCollateral;
    MockV3Aggregator public ethPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralisedStableCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        ethPriceFeed = MockV3Aggregator(
            dsce.getCollateralTokenPriceFeed(address(weth))
        );
    }

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethPriceFeed.updateAnswer(newPriceInt);
    // }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (userwithCollateral.length == 0) return;

        address sender = userwithCollateral[
            addressSeed % userwithCollateral.length
        ];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(sender);

        uint256 maxDscToMint = collateralValueInUsd / 2;
        if (maxDscToMint <= totalDscMinted) {
            console.log("Revert: maxDscToMint <= totalDscMinted");
            return;
        }
        maxDscToMint -= totalDscMinted;

        console.log("maxDscToMint: %s", maxDscToMint);

        amount = bound(amount, 0, maxDscToMint);
        if (amount == 0) {
            console.log("Revert: amount is zero after bounding");
            return;
        }

        console.log("Minting DSC: sender = %s, amount = %s", sender, amount);

        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
        timemintiscalled++;
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);

        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        userwithCollateral.push(msg.sender);
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToken = dsce.getCollateralBalanceOfUser(
            address(collateral),
            msg.sender
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralToken);
        if (amountCollateral == 0) return;
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    // Helper Functions
    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
