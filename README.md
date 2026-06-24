# Detecting Compromised Liquidity Vulnerabilities in Smart Contracts Using State-Based Formal Verification

**Bachelor's Thesis Artifact**
Abdullah Mohamed Elsayed Boraei — Vrije Universiteit Amsterdam — June 2026

---

## Overview

This repository contains the artifact for the bachelor's thesis:

> *Detecting Compromised Liquidity Vulnerabilities in Smart Contracts Using State-Based Formal Verification*

The thesis investigates whether state-based model checking using NuXmv can detect compromised liquidity vulnerabilities in Ethereum smart contracts — conditions under which funds become permanently inaccessible to legitimate users — that static analysis tools such as Slither and Mythril fail to identify.

Three representative contracts were selected based on documented real-world impact. For each, a vulnerable and patched version was modeled as a finite-state system and verified using Computation Tree Logic (CTL) properties expressing the reachability of successful fund withdrawal.

---

## Repository Structure

```
.
├── models/
│   ├── kotet_vulnerable.smv          # King of the Ether Throne — vulnerable
│   ├── kotet_patched.smv             # King of the Ether Throne — patched
│   ├── auction_vulnerable.smv        # SimpleAuction — vulnerable
│   ├── auction_patched.smv           # SimpleAuction — patched
│   ├── parity_vulnerable.smv         # Parity WalletLibrary — vulnerable (composed)
│   └── parity_patched.smv            # Parity WalletLibrary — patched
└── contracts/
    ├── KingOfTheEtherThrone_vulnerable.sol
    ├── KingOfTheEtherThrone_patched.sol
    ├── SimpleAuction.sol
    ├── ParityWalletLibrary_vulnerable.sol
    └── ParityWalletLibrary_patched.sol
```

---

## Case Studies

| Contract | Year | Loss | Vulnerability Class |
|---|---|---|---|
| King of the Ether Throne | 2016 | ~98 ETH | Unchecked `.send()` return value (SWC-104) |
| SimpleAuction | Canonical | N/A | DoS via reverting fallback (SWC-113) |
| Parity WalletLibrary | 2017 | ~$150M USD | Unprotected `selfdestruct` + uninitialised library (SWC-106, SWC-124) |

---

## Verification Results

All models were verified using NuXmv 2.2.0. Results are reproducible in under one second per model on any standard laptop.

| Contract | Version | CTL Property | Result |
|---|---|---|---|
| KotET | Vulnerable | `AG(debt → EF(¬debt))` | **FALSE** — counterexample at depth 3 |
| KotET | Patched | `AG(pending → EF(success))` | TRUE |
| SimpleAuction | Vulnerable | `AG(open → EF(recovered))` | **FALSE** — counterexample at depth 2 |
| SimpleAuction | Patched | `AG(pending → EF(success))` | TRUE |
| Parity | Vulnerable | `AG(EF(xfer))` | **FALSE** — counterexample at depth 4 |
| Parity | Vulnerable | `AG(dead → AG(¬xfer))` | TRUE† |
| Parity | Patched | `AG(EF(xfer))` | TRUE |

† Confirms vulnerability: once the library is DEAD, funds are permanently locked.

---

## Requirements

- **NuXmv 2.2.0** — download from [https://nuxmv.fbk.eu](https://nuxmv.fbk.eu)
- No other dependencies required. NuXmv reads `.smv` files directly.

---

## Installation

```bash
# 1. Clone this repository
git clone https://github.com/Abdullah-Boraei/compromised-liquidity-formal-verification
cd compromised-liquidity-formal-verification

# 2. Download NuXmv 2.2.0 for your OS from https://nuxmv.fbk.eu
#    and add the binary to your PATH

# 3. Verify the installation
nuXmv --version
```

---

## Running the Models

Run each model individually:

```bash
nuXmv models/kotet_vulnerable.smv
nuXmv models/kotet_patched.smv
nuXmv models/auction_vulnerable.smv
nuXmv models/auction_patched.smv
nuXmv models/parity_vulnerable.smv
nuXmv models/parity_patched.smv
```

Or run all at once and save output:

```bash
for f in models/*.smv; do
  echo "=== $f ===" && nuXmv "$f"
done
```

---

## Expected Output

**Vulnerable contracts** produce a property violation with a counterexample trace. For example, `kotet_vulnerable.smv`:

```
-- specification AG (debt_outstanding = TRUE -> EF debt_outstanding = FALSE)  is false
-- as demonstrated by the following execution sequence
Trace Description: CTL Counterexample
Trace Type: Counterexample
  -> State: 1.1 <-
    king_type = NONE
    debt_outstanding = FALSE
  -> State: 1.2 <-
    king_type = CONTRACT
  -> State: 1.3 <-
    king_type = EOA
    debt_outstanding = TRUE
```

**Patched contracts** produce a clean verification pass. For example, `kotet_patched.smv`:

```
-- specification AG (has_pending = TRUE -> EF withdraw_success = TRUE)  is true
```

---

## Translation Rules

The Solidity-to-NuXmv translation follows six explicit rules documented in Section 5.1 of the thesis:

1. **States** — each distinct combination of security-relevant storage variable values defines a state
2. **Transitions** — each public/external function call is a labeled transition
3. **Guards** — `require()` conditions are encoded as transition guards
4. **Actions** — storage variable updates become state variable assignments
5. **Marker states** — a designated variable represents successful fund withdrawal
6. **Abstraction boundary** — precise arithmetic is abstracted to Boolean flags where it does not affect reachability

---

## Adapting to New Contracts

To apply this methodology to a new Solidity contract:

1. Identify the security-relevant storage variables (those that affect fund accessibility)
2. Identify the marker state (the function that represents successful withdrawal)
3. Encode each public function as a NuXmv transition with guards from `require()` conditions
4. Write a CTL property of the form `AG(φ -> EF(marker = TRUE))`
5. Run NuXmv and inspect any counterexample traces

---

## Citation

If you use this artifact, please cite:

```
Abdullah Mohamed Elsayed Boraei. Detecting Compromised Liquidity Vulnerabilities 
in Smart Contracts Using State-Based Formal Verification. Bachelor's Thesis, 
Vrije Universiteit Amsterdam, June 2026.
```

---

## License

This artifact is made available for academic and research purposes.
The Solidity contracts are either original open-source code, simplified academic
reproductions, or canonical examples from public documentation.

---

## Contact

Abdullah Mohamed Elsayed Boraei
abdullah.mohamed.elsayed.boraei@student.vu.nl
Vrije Universiteit Amsterdam
