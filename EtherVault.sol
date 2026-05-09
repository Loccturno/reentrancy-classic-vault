// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

contract EtherVault {
    mapping(address => uint256) public balances;
    mapping(address => uint256) public lastDeposit;
    address public owner;
    uint256 public totalDeposits;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    function deposit() external payable {
        require(msg.value > 0, "Must send ETH");
        balances[msg.sender] += msg.value;
        lastDeposit[msg.sender] = block.timestamp;
        totalDeposits += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 _amount) external {
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        require(_amount > 0, "Amount must be > 0");

        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed");

        balances[msg.sender] -= _amount;
        totalDeposits -= _amount;

        emit Withdraw(msg.sender, _amount);
    }

    function withdrawAll() external {
        uint256 bal = balances[msg.sender];
        require(bal > 0, "No balance");
        balances[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: bal}("");
        require(success, "Transfer failed");
        totalDeposits -= bal;
        emit Withdraw(msg.sender, bal);
    }

    function getBalance(address _user) external view returns (uint256) {
        return balances[_user];
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
