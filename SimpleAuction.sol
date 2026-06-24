// SPDX-License-Identifier: GPL-3.0
// SimpleAuction — Vulnerable Version
// Source: Solidity official documentation (https://docs.soliditylang.org)
// Section: "Blind Auction" / "Simple Open Auction" example.
//
// KNOWN VULNERABILITY: DoS via revert in push-payment pattern (SWC-113).
// The vulnerable version uses a push pattern: when a new bid comes in,
// it immediately tries to refund the previous highest bidder via transfer().
// If the previous bidder is a contract with a reverting fallback, the
// entire claimThrone() call reverts — no new bids can ever succeed.
// The auction is permanently frozen at the attacker's bid.
//
// COMPROMISED LIQUIDITY SCENARIO:
// - Attacker deploys a contract with a reverting fallback.
// - Attacker's contract bids (becoming highestBidder).
// - Any future legitimate bidder calls bid() — it tries to refund
//   the attacker's contract — the fallback reverts — bid() reverts.
// - No one can outbid the attacker; auctionEnd() is unreachable for
//   legitimate bidders. Funds that could have been bid are locked out.
//
// For EFSM modeling purposes:
//   States: {OPEN, ENDED}
//   Transitions: bid(), auctionEnd()
//   Key variable: highestBidder (can be an attacker contract)
//   Blocking state: highestBidder.transfer() reverts in bid() body
//   Marker state: auctionEnd() called successfully

pragma solidity ^0.7.0;

contract SimpleAuction_Vulnerable {

    address payable public beneficiary;
    uint public auctionEndTime;

    address public highestBidder;
    uint public highestBid;

    bool public ended;

    event HighestBidIncreased(address bidder, uint amount);
    event AuctionEnded(address winner, uint amount);

    constructor(uint _biddingTime, address payable _beneficiary) {
        beneficiary = _beneficiary;
        auctionEndTime = block.timestamp + _biddingTime;
    }

    function bid() external payable {
        require(block.timestamp <= auctionEndTime, "Auction already ended");
        require(msg.value > highestBid, "There already is a higher bid");

        if (highestBid != 0) {
            // ---------------------------------------------------------------
            // VULNERABILITY: push refund to previous highest bidder.
            // If highestBidder is a contract with a reverting fallback,
            // this transfer() throws, reverting the entire bid() call.
            // No future bid() call can succeed. Auction is frozen.
            // ---------------------------------------------------------------
            payable(highestBidder).transfer(highestBid);
        }

        highestBidder = msg.sender;
        highestBid = msg.value;
        emit HighestBidIncreased(msg.sender, msg.value);
    }

    function auctionEnd() external {
        require(block.timestamp >= auctionEndTime, "Auction not yet ended");
        require(!ended, "auctionEnd has already been called");

        ended = true;
        emit AuctionEnded(highestBidder, highestBid);

        beneficiary.transfer(highestBid);
    }
}


// =============================================================================
// SimpleAuction — Patched Version
// FIX: Pull-over-push withdrawal pattern.
// Refunds are credited to a mapping; bidders call withdraw() themselves.
// A reverting fallback in a bidder contract can no longer block the auction.
//
// For EFSM modeling purposes:
//   States: {OPEN, ENDED}
//   Transitions: bid(), auctionEnd(), withdraw()
//   Marker state: withdraw() completes — all bidders can retrieve funds
//   Blocking state: none (by design)
// =============================================================================

pragma solidity ^0.7.0;

contract SimpleAuction_Patched {

    address payable public beneficiary;
    uint public auctionEndTime;

    address public highestBidder;
    uint public highestBid;

    // Pending returns for all outbid participants
    mapping(address => uint) public pendingReturns;

    bool public ended;

    event HighestBidIncreased(address bidder, uint amount);
    event AuctionEnded(address winner, uint amount);
    event Withdrawal(address bidder, uint amount);

    constructor(uint _biddingTime, address payable _beneficiary) {
        beneficiary = _beneficiary;
        auctionEndTime = block.timestamp + _biddingTime;
    }

    function bid() external payable {
        require(block.timestamp <= auctionEndTime, "Auction already ended");
        require(msg.value > highestBid, "There already is a higher bid");

        if (highestBid != 0) {
            // FIX: Credit the previous highest bidder rather than pushing.
            // Their fallback function is never called here.
            pendingReturns[highestBidder] += highestBid;
        }

        highestBidder = msg.sender;
        highestBid = msg.value;
        emit HighestBidIncreased(msg.sender, msg.value);
    }

    // Bidders pull their own refund — marker-state transition for EFSM.
    function withdraw() external returns (bool) {
        uint amount = pendingReturns[msg.sender];
        if (amount > 0) {
            // Zero first to prevent reentrancy
            pendingReturns[msg.sender] = 0;
            if (!payable(msg.sender).send(amount)) {
                pendingReturns[msg.sender] = amount;
                return false;
            }
            emit Withdrawal(msg.sender, amount);
        }
        return true;
    }

    function auctionEnd() external {
        require(block.timestamp >= auctionEndTime, "Auction not yet ended");
        require(!ended, "auctionEnd has already been called");

        ended = true;
        emit AuctionEnded(highestBidder, highestBid);

        beneficiary.transfer(highestBid);
    }
}
