// SPDX-License-Identifier: UNLICENSED
// Parity WalletLibrary — Vulnerable Version (Simplified)
// Based on the Parity MultiSig Wallet library deployed July 20, 2017.
// Original on-chain address: 0x863df6bfa4469f3ead0be8f9f2aae51c91a907b4
//
// This is a SIMPLIFIED ACADEMIC REPRODUCTION for EFSM modeling purposes.
// It preserves the exact vulnerability class and state structure of the
// original while omitting production features unrelated to the attack.
//
// KNOWN VULNERABILITY: Unprotected library initialization + delegatecall suicide.
// The WalletLibrary contract was designed to be called via delegatecall from
// individual Wallet stub contracts. However, the library itself was deployed
// without calling its own initWallet() — leaving it unowned and uninitialized.
//
// Attack sequence (Nov 6, 2017 — devops199):
// Transaction 1: devops199 calls initWallet([devops199], 1, 0) on the library.
//   -> isowner[devops199] = true; m_numOwners = 1; m_required = 1.
//   -> devops199 is now the sole owner of the library contract itself.
// Transaction 2: devops199 calls kill(devops199) on the library.
//   -> selfdestruct(devops199) executes — library code is wiped.
//   -> All Wallet stubs that delegatecall to this address now call dead code.
//   -> Every multisig wallet is permanently frozen. ~150M USD locked.
//
// COMPROMISED LIQUIDITY SCENARIO:
//   Every Wallet stub's execute(), confirm(), and changeOwner() functions
//   delegatecall to the library. After selfdestruct, delegatecall to a
//   dead address returns success with empty data — no state changes occur.
//   No transaction can ever be executed from any affected wallet.
//
// For EFSM modeling purposes (library contract):
//   States: {UNINITIALIZED, INITIALIZED, DEAD}
//   Transitions: initWallet(), kill()
//   Marker state: execute() completes — funds withdrawn from a wallet
//   Blocking state: DEAD — delegatecall returns empty; execute() is no-op
//
// For EFSM modeling purposes (wallet stub):
//   States: {ACTIVE, FROZEN}
//   Transitions: execute() [via delegatecall], library enters DEAD state
//   Blocking state: FROZEN — no execution path leads to fund transfer

pragma solidity ^0.4.15;

// ----------------------------------------------------------------------------
// Simplified multiowned base — manages owner list and required confirmations.
// In the original, this logic lived in the library and was shared via
// delegatecall. Here it is inlined for readability.
// ----------------------------------------------------------------------------
contract multiowned {

    // owner data
    uint constant c_maxOwners = 250;
    uint public m_required;
    uint public m_numOwners;
    mapping(address => uint) public m_ownerIndex;
    mapping(uint => address) public m_owners;

    // pending operations
    mapping(bytes32 => uint) public m_pendingIndex;
    mapping(uint => bytes32) public m_pending;
    uint public m_pendingCount;

    modifier onlyOwner {
        require(isOwner(msg.sender));
        _;
    }

    // -----------------------------------------------------------------------
    // VULNERABILITY ENTRY POINT: initMultiowned is public and unguarded.
    // In the deployed library, this was callable by anyone since the library
    // was never initialized on deployment.
    // -----------------------------------------------------------------------
    function initMultiowned(address[] _owners, uint _required) internal {
        m_numOwners = _owners.length;
        m_required = _required;
        for (uint i = 0; i < _owners.length; ++i) {
            m_owners[1 + i] = _owners[i];
            m_ownerIndex[_owners[i]] = 1 + i;
        }
    }

    function isOwner(address _addr) public view returns (bool) {
        return m_ownerIndex[_addr] > 0;
    }

    function changeOwner(address _from, address _to) external onlyOwner {
        uint ownerIndex = m_ownerIndex[_from];
        require(ownerIndex > 0);
        m_owners[ownerIndex] = _to;
        m_ownerIndex[_from] = 0;
        m_ownerIndex[_to] = ownerIndex;
    }
}

// ----------------------------------------------------------------------------
// WalletLibrary — the shared library contract that was killed.
// In production, all wallet stubs delegatecalled into this contract.
// ----------------------------------------------------------------------------
contract WalletLibrary is multiowned {

    bool public initialized;

    event Deposit(address from, uint value);
    event SingleTransact(address owner, uint value, address to, bytes data);
    event Kill(address by);

    // -----------------------------------------------------------------------
    // VULNERABILITY: initWallet is public with no initialized guard.
    // Any caller can invoke this on the library contract directly (not via
    // delegatecall from a wallet stub) and become an owner of the library.
    // -----------------------------------------------------------------------
    function initWallet(address[] _owners, uint _required, uint /*_daylimit*/) public {
        // MISSING CHECK: require(!initialized) — this was the fix.
        // Without it, anyone can reinitialize and seize ownership.
        initMultiowned(_owners, _required);
        initialized = true;
    }

    // -----------------------------------------------------------------------
    // VULNERABILITY: kill() is owner-gated, but after initWallet() above
    // an attacker IS the owner. This call permanently destroys the library.
    // -----------------------------------------------------------------------
    function kill(address _to) external onlyOwner {
        emit Kill(msg.sender);
        selfdestruct(_to);
    }

    // Normal wallet operations — delegatecalled from wallet stubs.
    function execute(address _to, uint _value, bytes _data) external onlyOwner returns (bytes32) {
        require(initialized);
        if (_data.length == 0) {
            _to.transfer(_value);
            emit SingleTransact(msg.sender, _value, _to, _data);
        }
        return 0;
    }

    // Accept deposits
    function() public payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }
}

// ----------------------------------------------------------------------------
// Wallet stub — one deployed per user/organization.
// Holds actual funds; delegates all logic to WalletLibrary via delegatecall.
// After the library is killed, all delegatecalls return empty data.
// The wallet is permanently frozen.
// ----------------------------------------------------------------------------
contract Wallet {

    address public libraryAddress;

    event Deposit(address from, uint value);

    constructor(address _library) public {
        libraryAddress = _library;
        // In the original, the wallet called initWallet here via delegatecall.
        // That initialization populated storage slots shared with the library's
        // multiowned state, which is why the library's uninitialized state mattered.
    }

    // -----------------------------------------------------------------------
    // All calls are forwarded to the library via delegatecall.
    // After selfdestruct of the library, delegatecall returns (true, "").
    // No state changes occur. The wallet is frozen — funds inaccessible.
    // -----------------------------------------------------------------------
    function() public payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        } else {
            address lib = libraryAddress;
            assembly {
                let ptr := mload(0x40)
                calldatacopy(ptr, 0, calldatasize)
                let result := delegatecall(gas, lib, ptr, calldatasize, ptr, 0)
                returndatacopy(ptr, 0, returndatasize)
                switch result
                case 0 { revert(ptr, returndatasize) }
                default { return(ptr, returndatasize) }
            }
        }
    }

    function getLibraryAddress() external view returns (address) {
        return libraryAddress;
    }
}
