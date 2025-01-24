// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;
import {Test, console} from "lib/forge-std/src/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStablecoin.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    error DSCEngine_NeedMoreThanZero();
    DeployDSC deployer;
    DSCEngine dsc;
    DecentralisedStableCoin dsce;
    HelperConfig helperconfig;
    address weth;
    address wethUsdPriceFeed;
    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsce, dsc, helperconfig) = deployer.run();
        (wethUsdPriceFeed, , weth, , ) = helperconfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, 10 ether);

        // Access other fields as needed
    }

    ///////////////////////////
    // Constructor Tests///////
    ///////////////////////////
    address[] public tokenAddresses;
    address[] public PriceFeedAddresses;
    address ethUsdPriceFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address btcUsdPriceFeed = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        PriceFeedAddresses.push(ethUsdPriceFeed);
        PriceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine_TokenAddressAndPriceFeedAddressMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, PriceFeedAddresses, address(dsc));
    }

    ////////////////
    ///Price TEst///
    ////////////////

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;

        uint256 actualWeth = dsc.getAmountUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsc.getValueUSD(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine_NeedMoreThanZero.selector);
        dsc.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertwithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_isNotAllowedToken.selector);
        dsc.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsc), AMOUNT_COLLATERAL);
        dsc.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();

        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsc
            .getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        console.log(collateralValueInUsd);
        uint256 expectedCollateralValueinUsd = dsc.getAmountUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedCollateralValueinUsd);
    }
}
