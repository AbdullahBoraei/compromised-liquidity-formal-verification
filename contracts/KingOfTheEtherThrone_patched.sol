// SPDX-License-Identifier: UNLICENSED
// King of the Ether Throne — Patched Version
// Based on the revised contract published post-February 2016 post-mortem.
// Ref: http://www.kingoftheether.com/contract-safety-checklist.html
//
// FIX APPLIED: Pull-over-push withdrawal pattern (SWC-104 remediation).
// Instead of pushing compensation to the previous monarch immediately
// (where a failed send locks funds), the contract now credits a balance
// mapping. The previous monarch must call withdraw() themselves.
// This eliminates the dependency on the recipient's fallback function.
//
// EFSM MODELING NOTE:
// Adding withdraw() introduces an explicit marker-state transition.
// The EFSM now has a designated SUCCESS state reachable from any
// credited balance, making non-blocking verification well-defined.
//
// For EFSM modeling purposes:
//   States: {EMPTY, HAS_KING, PENDING_WITHDRAWAL}
//   Transitions: claimThrone(), withdraw()
//   Marker state: withdraw() completes successfully
//   Blocking state: none (by design — this is the patched version)

pragma solidity ^0.4.24;

contract KingOfTheEtherThronePatched {

    address public king;
    uint public balance;
    mapping(address => uint) public pendingWithdrawals;

    uint public constant WIZARD_COMMISSION_PERMILLE = 50; // 5%
    address public wizard;

    event ThroneClaimed(address indexed newKing, uint newBalance);
    event WithdrawalMade(address indexed recipient, uint amount);
    event CompensationFailed(address indexed recipient, uint amount);

    constructor() public {
        wizard = msg.sender;
        king = msg.sender;
        balance = 0;
    }

    // Anyone can claim the throne by sending more ETH than the current balance.
    function claimThrone() external payable {
        require(msg.value > balance, "Must pay more than current balance to claim throne");

        uint fee = msg.value * WIZARD_COMMISSION_PERMILLE / 1000;
        uint compensation = balance; // previous king's compensation = old balance

        // Credit wizard fee — pull pattern
        pendingWithdrawals[wizard] += fee;

        // Credit previous king — pull pattern (FIX: no push, no .send())
        if (king != address(0) && compensation > 0) {
            pendingWithdrawals[king] += compensation;
            emit CompensationFailed(king, compensation); // just for trace; real credit above
        }

        // Update throne state
        balance = msg.value;
        king = msg.sender;

        emit ThroneClaimed(msg.sender, msg.value);
    }

    // Previous kings withdraw their own compensation.
    // This is the marker-state transition for EFSM non-blocking verification.
    function withdraw() external {
        uint amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        require(msg.sender != king, "Current king cannot withdraw during reign");

        // Effects before interaction (reentrancy protection)
        pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = msg.sender.call.value(amount)("");
        require(success, "Transfer failed");

        emit WithdrawalMade(msg.sender, amount);
    }

    function currentClaimPrice() external view returns (uint) {
        return balance + 1; // must exceed current balance
    }

    function pendingWithdrawal(address addr) external view returns (uint) {
        return pendingWithdrawals[addr];
    }
}
