// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/EtherVaultFixed.sol";
import "../src/Attacker.sol";

/**
 * @title EtherVaultFixedTest
 * @notice Symmetric proof: the same attack that drains EtherVault
 *         is fully blocked by EtherVaultFixed.
 *
 * Defense layers verified:
 *   1. CEI ordering — state updated before external call
 *   2. ReentrancyGuard — mutex catches re-entry attempts
 *   3. Solidity 0.8 checked arithmetic — no unchecked block here
 */
contract EtherVaultFixedTest is Test {
    EtherVaultFixed public vault;
    Attacker public attacker;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public attackerEOA = address(0xBAD);

    function setUp() public {
        // Identical setup to the vulnerable test — only the vault changes
        vault = new EtherVaultFixed();

        vm.deal(alice, 5 ether);
        vm.deal(bob, 5 ether);

        vm.prank(alice);
        vault.deposit{value: 5 ether}();

        vm.prank(bob);
        vault.deposit{value: 5 ether}();

        attacker = new Attacker(payable(address(vault)));
        vm.deal(attackerEOA, 1 ether);
    }

    function test_AttackIsBlockedOnFixedVault() public {
        // The attack must revert — either from CEI (insufficient balance
        // on re-entry) or from the ReentrancyGuard mutex.
        vm.prank(attackerEOA);
        vm.expectRevert();
        attacker.attack{value: 1 ether}();
    }

    function test_VaultStateUnchangedAfterFailedAttack() public {
        // Attempt the attack — it will revert
        vm.prank(attackerEOA);
        try attacker.attack{value: 1 ether}() {
            // If we reach this branch, the attack didn't revert — fail
            revert("Attack should have reverted");
        } catch {
            // Expected — the entire transaction is rolled back
        }

        // After the failed attack, the vault is intact:
        //   - 10 ETH still held
        //   - Honest balances preserved
        //   - Attacker contract has nothing
        assertEq(address(vault).balance, 10 ether, "Vault should still hold 10 ETH");
        assertEq(vault.balances(alice), 5 ether, "Alice's balance unchanged");
        assertEq(vault.balances(bob), 5 ether, "Bob's balance unchanged");
        assertEq(address(attacker).balance, 0, "Attacker contract should be empty");
    }

    function test_HonestWithdrawStillWorksOnFixed() public {
        // After the failed attack, honest users can still withdraw normally
        vm.prank(attackerEOA);
        try attacker.attack{value: 1 ether}() {} catch {}

        // Alice withdraws her honest deposit
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        vault.withdraw(5 ether);

        assertEq(alice.balance, aliceBalanceBefore + 5 ether, "Alice should receive her 5 ETH");
        assertEq(vault.balances(alice), 0, "Alice's vault balance should be zero");
    }
}