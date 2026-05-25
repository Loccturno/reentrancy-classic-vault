// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/EtherVault.sol";
import "../src/Attacker.sol";

/**
 * @title ReentrancyAttackTest
 * @notice Proof-of-concept that demonstrates the classic single-function
 *         reentrancy attack draining the vulnerable EtherVault.
 *
 * Scenario reproduced:
 *   - Vault holds 10 ETH from honest users
 *   - Attacker uses 1 ETH as bait
 *   - After attack(), the vault is empty and the attacker contract
 *     holds 11 ETH (1 recovered + 10 stolen)
 */
contract ReentrancyAttackTest is Test {
    EtherVault public vault;
    Attacker public attacker;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public attackerEOA = address(0xBAD);

    function setUp() public {
        // Deploy the vulnerable vault
        vault = new EtherVault();

        // Fund honest users and have them deposit
        vm.deal(alice, 5 ether);
        vm.deal(bob, 5 ether);

        vm.prank(alice);
        vault.deposit{value: 5 ether}();

        vm.prank(bob);
        vault.deposit{value: 5 ether}();

        // Deploy attacker contract with vault address
        attacker = new Attacker(payable(address(vault)));

        // Fund the attacker EOA with 1 ETH bait
        vm.deal(attackerEOA, 1 ether);
    }

    function test_VaultStartsWith10Ether() public {
        // Sanity check: setup is correct
        assertEq(address(vault).balance, 10 ether);
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.balances(alice), 5 ether);
        assertEq(vault.balances(bob), 5 ether);
    }

    function test_AttackDrainsVault() public {
        // ============ BEFORE ============
        uint256 vaultBalanceBefore = address(vault).balance;
        uint256 attackerContractBalanceBefore = address(attacker).balance;

        assertEq(vaultBalanceBefore, 10 ether, "Vault should start with 10 ETH");
        assertEq(attackerContractBalanceBefore, 0, "Attacker contract should start empty");

        // ============ ATTACK ============
        vm.prank(attackerEOA);
        attacker.attack{value: 1 ether}();

        // ============ AFTER ============
        uint256 vaultBalanceAfter = address(vault).balance;
        uint256 attackerContractBalanceAfter = address(attacker).balance;

        // The vault is drained
        assertEq(vaultBalanceAfter, 0, "Vault should be fully drained");

        // The attacker contract holds 11 ETH:
        //   1 ETH the attacker originally deposited (recovered)
        // + 10 ETH stolen from honest users
        assertEq(attackerContractBalanceAfter, 11 ether, "Attacker should have stolen 10 ETH + 1 ETH bait");

        // Net profit: 10 ETH
        uint256 netProfit = attackerContractBalanceAfter - 1 ether;
        assertEq(netProfit, 10 ether, "Net profit should be 10 ETH");
    }

    function test_VaultAccountingIsCorruptedAfterAttack() public {
        // Run the attack
        vm.prank(attackerEOA);
        attacker.attack{value: 1 ether}();

        // The vault's bookkeeping is now nonsensical:
        // balances[attacker] underflowed during stack unwinding
        // (Solidity 0.7 has no built-in overflow checks)
        uint256 corruptedBalance = vault.balances(address(attacker));

        // The balance is now a massive number close to 2^256 - 1
        // We assert it's "absurd" — far larger than any honest balance
        assertGt(corruptedBalance, 2**128, "Attacker's balance should have underflowed to an absurd value");
    }

    function test_HonestUsersCannotWithdrawAfterAttack() public {
        // Run the attack
        vm.prank(attackerEOA);
        attacker.attack{value: 1 ether}();

        // Alice tries to withdraw her honest deposit — fails because vault is empty
        vm.prank(alice);
        vm.expectRevert("Transfer failed");
        vault.withdraw(5 ether);
    }
}
