// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {DecentralisedStableCoin} from "src/DecentralisedStablecoin.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/library/OracleLib.sol";

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

/**
 *@title DSCEngine
 *@author Sahil Kaushik
 * system is desingend to be minimal as possible, and have tokens maintain a $1 peg
 * Properties:
 * -Exogenoues Collateral
 * -Dollar Pegged
 * -Algorithmicallly stable
 *
 * we should have more collateral "overcollateralised" collateral should be greater than amount of dsc.
 * it is similar to DAI with no ogovernance,no fees and was only backed by WETH and WBTC
 *Relative Stability pegged to usd
 *
 *@notice This contract is core of the DSC System. It handles all the logic for mining and redeeming DSC, as well ass depositing and withdraeing collateral.
 *@notice This contract is very loosely based on MakerDao DSS(DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    //////////////////
    // Errors       //
    //////////////////
    error DSCEngine_NeedMoreThanZero();
    error DSCEngine_TokenAddressAndPriceFeedAddressMustBeSameLength();
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor(uint256);
    error DSCEngine_MintFailed();
    error DSCEngine_HealthFactorOk();
    error DSCEngine_HealthFactorNotImproved();
    error DSCEngine_isNotAllowedToken();

    //////////////////
    // Types        //
    //////////////////
    using OracleLib for AggregatorV3Interface;
    ///////////////////////
    //State Variables    //
    ///////////////////////
    mapping(address token => address priceFeed) private s_price_Feeds;
    DecentralisedStableCoin private immutable i_dsc;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateraldeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 Min_HealthFactor = 1;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    address[] private s_CollateralToken;
    //////////////////
    // Evemts       //
    //////////////////
    event Collateraldeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event CollateralRedeemed(address, address, uint256, address);
    //////////////////
    // MODIFIERS    //
    //////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine_NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_price_Feeds[token] == address(0)) {
            revert DSCEngine_isNotAllowedToken();
        }
        _;
    }

    //////////////////
    // Functions    //
    //////////////////

    constructor(
        address[] memory tokenAddress,
        address[] memory priceFeedAddress,
        address dscAddress
    ) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine_TokenAddressAndPriceFeedAddressMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_price_Feeds[tokenAddress[i]] = priceFeedAddress[i];
            s_CollateralToken.push(tokenAddress[i]);
        }

        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    //////////////////////
    // External Func    //
    //////////////////////
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @param tokenCOllateralAddress the address of the token to deposit as collateral
     * @param amountCOllateral the amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateraldeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit Collateraldeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );

        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external moreThanZero(amountCollateral) nonReentrant {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        _revertIfHealthFacotrIsBroken(msg.sender);
    }

    /*
     * @notice follows CIE
     * @param amountDscToMInt amount of decentralised stable coin ot mint
     * @notice collateral value should be more than minimum thresshold
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFacotrIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (minted != true) {
            revert DSCEngine_MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFacotrIsBroken(msg.sender);
    }

    // if we do stat undercollateralisation , we needd someone to liquidate postions
    // 100 dollar backing 50 dollar dsc
    // 75 dollar backing 50 dollar dsc
    // liquiddator takes 75$ valing and burns off the 50 $ DSC
    // if someone is undercollateralised , we will pay i to liquidate them!!
    /*
* @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
* This is collateral that you're going to take from the user who is insolvent.
* In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
* @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
* @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
*
* @notice: You can partially liquidate a user.
* @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
* @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
to work.
* @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
anyone.
* For example, if the price of the collateral plummeted before anyone could be liquidated.
* Follows CEIs : Checks,Effects and Interactons 
*/
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= Min_HealthFactor) {
            revert DSCEngine_HealthFactorOk();
        }
        // we want to burn their dsc debt
        // And take their collateral
        // Bad User : 140$ Eth , 100$ DSC
        // DebtToCover = 100$
        // 100% dsc= ??? ETH ?
        uint256 tokenAmountFromDebtCovered = getAmountUsd(
            collateral,
            debtToCover
        );
        // and give them a 10 % bonus;
        // so we are giving the liquidaor 110 $ of weth ffor 100$ dsc;
        // we should implement a feature to liquidate int the event the protocol is insolvent
        //  and sweep extra amount into treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            user,
            msg.sender,
            collateral,
            totalCollateralRedeemed
        );
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine_HealthFactorNotImproved();
        }

        _revertIfHealthFacotrIsBroken(msg.sender);
    }

    function getAmountUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_price_Feeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getHealthFactor() external {}

    //////////////////////////////////
    //private internal view funcitns//
    //////////////////////////////////

    function _burnDsc(
        uint256 amount,
        address onBehalfOf,
        address dscFrom
    ) private moreThanZero(amount) {
        s_DSCMinted[onBehalfOf] -= amount;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amount);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
        i_dsc.burn(amount);
    }

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private {
        s_collateraldeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            amountCollateral,
            tokenCollateralAddress
        );
        bool sucess = IERC20(tokenCollateralAddress).transfer(
            msg.sender,
            amountCollateral
        );
        if (!sucess) {
            revert DSCEngine_TransferFailed();
        }
    }

    function getAccountInformation(
        address user
    )
        public
        view
        returns (uint256 toatlDscMinted, uint256 collateralValuedinUsd)
    {
        toatlDscMinted = s_DSCMinted[user];
        collateralValuedinUsd = getAccountCollateralValue(user);
    }

    /*
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can be liquidated.
     */

    function _healthFactor(address user) private view returns (uint256) {
        // total dsc minted
        // total collateral value
        (
            uint256 totalDscMinted,
            uint256 collateralValueinUSD
        ) = getAccountInformation(user);
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueinUSD *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFacotrIsBroken(address user) internal view {
        // Check heatlth factor if they have enough collateral
        //  revert if they dont have

        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < Min_HealthFactor) {
            revert DSCEngine_BreaksHealthFactor(userHealthFactor);
        }
    }

    //////////////////////////////////
    //public external view funcitns//
    //////////////////////////////////
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueinUsd) {
        // loop through each collateral token , get the amount they have deposited and map it to the pricee , to get usd vlaue
        for (uint256 i = 0; i < s_CollateralToken.length; i++) {
            address token = s_CollateralToken[i];
            uint256 amount = s_collateraldeposited[user][token];
            totalCollateralValueinUsd += getValueUSD(token, amount);
        }
        return totalCollateralValueinUsd;
    }

    function getValueUSD(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_price_Feeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();

        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_CollateralToken;
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_price_Feeds[token];
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateraldeposited[user][token];
    }
}
