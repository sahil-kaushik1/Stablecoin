// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

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
/*
 *@title DecentralizedStableCoin
 *@author Sahil Kaushik
 *Collateral: Exogenous (ETH & BTC)
 *Minting Algorithmic
 *Relative Stability pegged to usd
 *
 *this is the contract meant to be governed by DSCEngine. this contract is just the erc20 implemetation of our stablecoin system.
 */

import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    error DecentralisedStableCoin_MustBeMoreThanZero();
    error DecentralisedStableCoin_BurnAmountExceedsBalance();
    error DecentralisedStableCoin_ZeroAddress();

    constructor() ERC20("DecentralisedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralisedStableCoin_MustBeMoreThanZero();
        }
        if (_amount > balance) {
            revert DecentralisedStableCoin_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin_ZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralisedStableCoin_MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
