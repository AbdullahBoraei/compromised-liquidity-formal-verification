// SPDX-License-Identifier: UNLICENSED
// King of the Ether Throne — Vulnerable Version
// Original contract deployed February 2016 by Kieran Elby.
// Blockchain address: 0xb336a86e2feb1e87a328fcb7dd4d04de3df254d0
// Compiled with Solidity 0.2.1 (reproduced here in ^0.4.19 for accuracy to original).
//
// KNOWN VULNERABILITY: Unchecked return value on .send() (SWC-104).
// When the current monarch is a contract-based wallet (e.g. Mist wallet),
// the .send() forwards only 2300 gas. If the wallet's fallback function
// consumes more than this, the send fails silently. The contract does NOT
// check the return value, so execution continues: the new king is crowned
// and the previous monarch's compensation is permanently lost.
//
// COMPROMISED LIQUIDITY SCENARIO:
// - Alice (contract wallet) becomes queen by paying 10 ETH.
// - Bob pays 15 ETH to claim the throne.
// - KotET calls alice.send(10 ETH) — fails silently (insufficient gas).
// - Bob is crowned. Alice never receives her 10 ETH.
// - Alice's funds are locked inside the contract forever; she has no
//   withdraw function to retrieve them.
//
// Historical incident: Feb 6–8, 2016. Three transactions affected.
// 42.273 ETH + 7.77 ETH + one further refund failed silently.
// All ether was eventually refunded manually by the developer.
// Post-mortem: http://www.kingoftheether.com/postmortem.html
//
// For EFSM modeling purposes:
//   States: {EMPTY, HAS_KING}
//   Transitions: claimThrone(), fallback (implicit send to previous king)
//   Marker state (non-blocking target): previous king receives compensation
//   Blocking state: previous king is a contract; send fails; funds locked

pragma solidity ^0.4.19;

contract KingOfTheEtherThrone {

    struct Monarch {
        address etherAddress;
        string name;
        uint claimPrice;
        uint coronationBlock;
    }

    Monarch public currentMonarch;
    address public wizardAddress;

    uint public startingClaimPrice = 100 finney; // 0.1 ETH
    uint public claimPriceAdjustNum = 3;
    uint public claimPriceAdjustDen = 2;
    uint public wizardCommission = 50; // per-mille (5%)

    event ThroneClaimed(
        address indexed usurperEtherAddress,
        string usurperName,
        uint newClaimPrice
    );

    function KingOfTheEtherThrone() public {
        wizardAddress = msg.sender;
        currentMonarch = Monarch(
            wizardAddress,
            "[Vacant]",
            startingClaimPrice,
            block.number
        );
    }

    function() public payable {
        require(msg.value >= currentMonarch.claimPrice);

        uint wizardCommissionFee = msg.value * wizardCommission / 1000;
        uint compensation = msg.value - wizardCommissionFee;

        // ---------------------------------------------------------------
        // VULNERABILITY: unchecked return value.
        // If currentMonarch.etherAddress is a contract whose fallback
        // function requires more than 2300 gas, this send() will return
        // false but execution continues. Compensation is silently lost.
        // ---------------------------------------------------------------
        currentMonarch.etherAddress.send(compensation);

        wizardAddress.send(wizardCommissionFee);

        uint newClaimPrice =
            currentMonarch.claimPrice * claimPriceAdjustNum / claimPriceAdjustDen;

        ThroneClaimed(msg.sender, "", newClaimPrice);

        currentMonarch = Monarch(
            msg.sender,
            "",
            newClaimPrice,
            block.number
        );
    }

    function currentClaimPrice() public view returns (uint) {
        return currentMonarch.claimPrice;
    }
}
