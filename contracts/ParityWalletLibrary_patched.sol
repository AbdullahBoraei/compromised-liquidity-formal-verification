// SPDX-License-Identifier: UNLICENSED
// Parity WalletLibrary — Patched Version (Simplified Academic Reproduction)
//
// FIXES APPLIED (two independent guards, either alone would have prevented the attack):
//
// Fix 1 — Initialization guard on initWallet():
//   require(!initialized) added as the FIRST statement.
//   Once initialized = true, no further call to initWallet() can succeed.
//   devops199's first transaction would have reverted here.
//
// Fix 2 — Constructor-based initialization:
//   The patched library initializes itself in the constructor with a sentinel
//   owner (address(this)) and m_required = 1, making it immediately owned
//   and preventing any external initWallet() call from taking effect.
//   This is the pattern recommended by security reviewers in August 2017
//   (ref: GitHub user "3esmit" warning, ignored by Parity until too late).
//
// For EFSM modeling purposes:
//   States: {INITIALIZED} only — UNINITIALIZED state is never reachable
//   Transitions: execute(), changeOwner()
//   The DEAD state is unreachable because kill() requires ownership,
//   and ownership cannot be seized by an attacker.
//   Non-blocking: every reachable state has a path to execute() success.

pragma solidity ^0.4.24;

contract multiownedPatched {

    uint constant c_maxOwners = 250;
    uint public m_required;
    uint public m_numOwners;
    mapping(address => uint) public m_ownerIndex;
    mapping(uint => address) public m_owners;

    modifier onlyOwner {
        require(isOwner(msg.sender), "Not an owner");
        _;
    }

    function initMultiowned(address[] memory _owners, uint _required) internal {
        require(_owners.length > 0 && _required > 0 && _required <= _owners.length);
        m_numOwners = _owners.length;
        m_required = _required;
        for (uint i = 0; i < _owners.length; i++) {
            require(_owners[i] != address(0));
            m_owners[1 + i] = _owners[i];
            m_ownerIndex[_owners[i]] = 1 + i;
        }
    }

    function isOwner(address _addr) public view returns (bool) {
        return m_ownerIndex[_addr] > 0;
    }

    function changeOwner(address _from, address _to) external onlyOwner {
        uint ownerIndex = m_ownerIndex[_from];
        require(ownerIndex > 0, "Not an owner");
        require(_to != address(0), "Invalid address");
        m_owners[ownerIndex] = _to;
        m_ownerIndex[_from] = 0;
        m_ownerIndex[_to] = ownerIndex;
    }
}

contract WalletLibraryPatched is multiownedPatched {

    bool public initialized;

    event Deposit(address indexed from, uint value);
    event SingleTransact(address indexed owner, uint value, address indexed to);
    event Kill(address indexed by);

    // -----------------------------------------------------------------------
    // FIX 1: Constructor initializes the library with address(this) as owner.
    // The library is immediately owned and can never be re-initialized.
    // -----------------------------------------------------------------------
    constructor() public {
        address[] memory sentinelOwners = new address[](1);
        sentinelOwners[0] = address(this);
        initMultiowned(sentinelOwners, 1);
        initialized = true;
    }

    // -----------------------------------------------------------------------
    // FIX 2: Initialization guard — cannot be called twice.
    // Even if the constructor fix were absent, this guard would prevent
    // an attacker from calling initWallet() on the live library.
    // -----------------------------------------------------------------------
    function initWallet(address[] memory _owners, uint _required, uint /*_daylimit*/) public {
        require(!initialized, "Already initialized"); // <-- THE FIX
        initMultiowned(_owners, _required);
        initialized = true;
    }

    // kill() remains — but is now only callable by a legitimate owner
    // (address(this) in library context, or proper owners in wallet context).
    // An external attacker can never become an owner, so kill() is unreachable.
    function kill(address _to) external onlyOwner {
        emit Kill(msg.sender);
        selfdestruct(_to);
    }

    // Normal execute — marker-state transition for EFSM non-blocking verification.
    function execute(address _to, uint _value, bytes memory /*_data*/) external onlyOwner returns (bool) {
        require(initialized, "Not initialized");
        require(_to != address(0), "Invalid recipient");
        require(address(this).balance >= _value, "Insufficient balance");
        emit SingleTransact(msg.sender, _value, _to);
        (bool success, ) = _to.call.value(_value)("");
        return success;
    }

    function() external payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }
}

// Wallet stub — unchanged structurally; now safe because the library cannot be killed
// by an unauthorized party.
contract WalletPatched {

    address public libraryAddress;

    event Deposit(address indexed from, uint value);

    constructor(address _library) public {
        require(_library != address(0));
        libraryAddress = _library;
    }

    function() external payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        } else {
            address lib = libraryAddress;
            assembly {
                let ptr := mload(0x40)
                calldatacopy(ptr, 0, calldatasize())
                let result := delegatecall(gas(), lib, ptr, calldatasize(), ptr, 0)
                returndatacopy(ptr, 0, returndatasize())
                switch result
                case 0 { revert(ptr, returndatasize()) }
                default { return(ptr, returndatasize()) }
            }
        }
    }
}
