# Reentrancy Classic Vault

A hands-on exercise recreating the classic single-function reentrancy 
vulnerability — the same pattern that drained The DAO of $150M in 2016.

## What's inside

- `contracts/EtherVault.sol` — vulnerable contract (Solidity 0.7)
- `contracts/Attacker.sol` — exploit contract that drains the vault
- `contracts/EtherVaultFixed.sol` — patched version (CEI + ReentrancyGuard)
- `notes/attack-flow.md` — step-by-step walkthrough with state changes

## The bug

In `withdraw()`, the external call (`msg.sender.call{value: _amount}`) 
happens **before** the state update (`balances[msg.sender] -= _amount`).
This violates the Checks-Effects-Interactions pattern.

When the recipient is a contract with a malicious `receive()` function, 
it can re-enter `withdraw()` while `balances[attacker]` is still 
unchanged — draining the vault one withdrawal at a time.

## Severity

**Critical** — direct fund loss, fully exploitable, no preconditions 
beyond having any deposit.

## The fix

Two layers of defense:
1. **CEI ordering**: state updates before external calls
2. **`nonReentrant` modifier**: mutex lock from OpenZeppelin's ReentrancyGuard

See `EtherVaultFixed.sol` for the patched version.

## Why pragma 0.7?

Solidity 0.8+ introduces built-in arithmetic overflow/underflow checks, 
which would cause the underflow during stack unwinding to revert the 
entire transaction — neutralizing this naive attack.

The original DAO used Solidity 0.4.x. To preserve the authentic attack 
flow, this exercise uses 0.7 (no automatic checks).

In modern code, the same bug pattern still exists wherever devs use 
`unchecked { }` blocks for gas savings, or in pre-0.8 legacy contracts.

## Lessons learned

- External calls hand control to the callee — assume it's hostile
- CEI is not optional, it's load-bearing
- Defense in depth: pattern + library guard
- Compiler version matters for which exploits are viable
- The simplest bugs cost the most ($150M)

## References

- The DAO post-mortem (June 2016)
- ConsenSys Smart Contract Best Practices: Reentrancy
- OpenZeppelin ReentrancyGuard

---
*Part of my smart contract audit practice. Not for production use.*
