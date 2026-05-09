# Attack Flow — Step by Step

A walkthrough of how the `Attacker` contract drains the vulnerable 
`EtherVault`. Read this alongside the contract source code to follow 
along.

## Setup

Before the attack begins, we assume:

- **EtherVault** has been deployed and contains **10 ETH** from honest 
  users who deposited earlier.
- **Attacker** has been deployed, with the EtherVault address passed to 
  its constructor.
- The attacker EOA holds **1 ETH** that will be used as bait.

| Actor          | ETH balance | Notes                          |
| -------------- | ----------- | ------------------------------ |
| EtherVault     | 10          | From honest users' deposits    |
| Attacker (EOA) | 1           | About to be used in the attack |
| Attacker (contract) | 0     | Just deployed, empty           |

## Phase 1 — The deposit (looking legitimate)

The attacker calls `Attacker.attack{value: 1 ether}()`.

Inside `attack()`:

1. `attackAmount = 1 ether` is stored in state (the `receive()` 
   function will need this value later, since fallback functions 
   take no arguments).
2. `victim.deposit{value: 1 ether}()` is called — the vault now sees 
   the attacker contract as a normal user with a 1 ETH balance.

State after Phase 1:

| Actor               | ETH balance | balances[attacker] in vault |
| ------------------- | ----------- | --------------------------- |
| EtherVault          | 11          | 1                           |
| Attacker (contract) | 0           | —                           |

So far, nothing suspicious — this is the same state any honest user 
would be in after depositing.

## Phase 2 — The trigger

Still inside `attack()`, the next line is:

```solidity
victim.withdraw(attackAmount);
```

This calls into `EtherVault.withdraw(1 ether)`. Inside the vault:

```solidity
require(balances[msg.sender] >= _amount, "Insufficient balance");
require(_amount > 0, "Amount must be > 0");

(bool success, ) = msg.sender.call{value: _amount}(""); // ← here
require(success, "Transfer failed");

balances[msg.sender] -= _amount;     // ← state update happens AFTER
totalDeposits -= _amount;
```

The vault sends 1 ETH to `msg.sender` (the attacker contract) **before** 
updating `balances`. This hands execution control to the attacker while 
the vault's bookkeeping still believes the attacker has 1 ETH on deposit.

## Phase 3 — The reentrancy loop

When the attacker contract receives ETH, its `receive()` function fires:

```solidity
receive() external payable {
    if (address(victim).balance >= attackAmount) {
        victim.withdraw(attackAmount);
    }
}
```

The condition checks: *does the vault still have at least 1 ETH to 
give me?* If yes, call `withdraw(1 ether)` again.

Each re-entry:
- The vault re-runs `require(balances[msg.sender] >= _amount)` 
- `balances[attacker]` is **still 1** because the previous frame hasn't 
  reached the state update yet
- The check passes, another 1 ETH is sent, another `receive()` fires

Trace of the loop, frame by frame:

| Iter | Vault balance before | Vault balance after | Attacker contract ETH | balances[attacker] (in storage) |
| ---- | -------------------- | ------------------- | --------------------- | ------------------------------- |
| 1    | 11                   | 10                  | 1                     | **1** (stale)                   |
| 2    | 10                   | 9                   | 2                     | **1**                           |
| 3    | 9                    | 8                   | 3                     | **1**                           |
| 4    | 8                    | 7                   | 4                     | **1**                           |
| 5    | 7                    | 6                   | 5                     | **1**                           |
| 6    | 6                    | 5                   | 6                     | **1**                           |
| 7    | 5                    | 4                   | 7                     | **1**                           |
| 8    | 4                    | 3                   | 8                     | **1**                           |
| 9    | 3                    | 2                   | 9                     | **1**                           |
| 10   | 2                    | 1                   | 10                    | **1**                           |
| 11   | 1                    | 0                   | 11                    | **1**                           |
| 12   | 0                    | —                   | —                     | **1**                           |

At iteration 12, `address(victim).balance` is 0, which fails the 
`if (... >= 1 ether)` check in `receive()`. No more re-entry. The 
deepest call frame returns normally.

## Phase 4 — Stack unwinding

Now the call stack unwinds. Each suspended frame of `withdraw()` 
resumes from where it paused (right after the `call`):

```solidity
balances[msg.sender] -= _amount;     // Now this finally runs
totalDeposits -= _amount;
```

Frame 11 runs first (innermost): `balances = 1 - 1 = 0` ✓

Frame 10 runs next: `balances = 0 - 1 = ???`

In Solidity 0.7, arithmetic has no built-in overflow checks. So 
`0 - 1` underflows to `2^256 - 1` (a number close to 1.15 × 10^77). 
The remaining frames continue subtracting from this huge number with 
no revert.

Same thing happens to `totalDeposits` — it underflows but doesn't 
abort the transaction.

The transaction completes successfully.

## Phase 5 — Final state

| Actor               | ETH balance | balances[attacker] in vault |
| ------------------- | ----------- | --------------------------- |
| EtherVault          | 0           | 2^256 - 11 (garbage)        |
| Attacker (contract) | 11          | —                           |

The attacker contract now holds 11 ETH:
- 1 ETH it originally deposited (recovered)
- 10 ETH stolen from the honest users

## Phase 6 — Cashing out

The attacker EOA calls `Attacker.drain()`, which transfers the 11 ETH 
from the contract to the EOA wallet. The honest users' funds are gone, 
the vault is empty, and the attacker is up 10 ETH net profit (minus 
gas fees).

## Why this works

The bug is a single ordering mistake: the external `call` happens 
**before** the state update. Three things have to be true for the 
exploit to work:

1. **External call before state update** — the violation of CEI
2. **Recipient is a contract** — only contracts have a `receive()` / 
   `fallback()` that can re-enter
3. **No reentrancy guard** — no mutex lock to detect the re-entry

Remove any one of these and the attack fails.

## Why it would not work in Solidity 0.8+

From version 0.8.0 onwards, arithmetic operations have **built-in 
overflow and underflow checks**. The line `balances[msg.sender] -= 
_amount` would revert during stack unwinding the moment the value 
goes below zero — taking the entire transaction with it.

This means the naive form of this attack does not work on a vanilla 
0.8+ contract. **However**, the same pattern is still exploitable when:

- Developers use `unchecked { }` blocks for gas savings
- The bug is in a pre-0.8 legacy contract
- A more sophisticated variant is used (cross-function reentrancy, 
  read-only reentrancy via stale view functions, etc.)

The original DAO ran on Solidity 0.4.x, where this exact pattern 
drained roughly $150M.

## How the fix breaks the attack

`EtherVaultFixed.sol` reorders the function so state updates happen 
before the external call:

```solidity
balances[msg.sender] -= _amount;     // EFFECTS first
totalDeposits -= _amount;

(bool success, ) = msg.sender.call{value: _amount}(""); // INTERACTIONS last
require(success, "Transfer failed");
```

Now when `receive()` re-enters and tries `withdraw(1 ether)`:
- `balances[attacker]` is already 0
- `require(balances[msg.sender] >= _amount)` fails
- The re-entry call reverts

The `nonReentrant` modifier provides a second line of defense — even 
if a future code change accidentally reintroduces a CEI violation, 
the mutex will catch it.

## Lessons

- External calls hand control to untrusted code. Treat them as hostile.
- State updates before external calls is not a style preference — it 
  is load-bearing structure.
- Compiler version changes which exploits are viable, but does not 
  fix logic bugs.
- The simplest patterns cause the largest losses. Always look first 
  for the textbook bugs before reaching for exotic ones.
