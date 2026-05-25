// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title EtherVaultFixed
 * @notice Patched version of the vulnerable EtherVault contract.
 *
 * Two layers of defense applied:
 *   1. CEI pattern (Checks-Effects-Interactions) — all state updates 
 *      happen BEFORE any external call.
 *   2. ReentrancyGuard — mutex lock on functions that send ETH, as 
 *      a safety net in case CEI is missed elsewhere (defense in depth).
 *
 * In production code, prefer importing from OpenZeppelin:
 *   import "openzeppelin/contracts/security/ReentrancyGuard.sol";
 *
 * The guard is inlined here for educational clarity — anyone reading 
 * this repo can see exactly how the mutex works without chasing imports.
 */

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract EtherVaultFixed is ReentrancyGuard {
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

    function withdraw(uint256 _amount) external nonReentrant {
        // CHECKS
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        require(_amount > 0, "Amount must be > 0");

        // EFFECTS — all state updates BEFORE any external call
        balances[msg.sender] -= _amount;
        totalDeposits -= _amount;

        // INTERACTIONS — external call last
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed");

        emit Withdraw(msg.sender, _amount);
    }

    function withdrawAll() external nonReentrant {
        // CHECKS
        uint256 bal = balances[msg.sender];
        require(bal > 0, "No balance");

        // EFFECTS — all state updates first (including totalDeposits!)
        balances[msg.sender] = 0;
        totalDeposits -= bal;

        // INTERACTIONS — external call last
        (bool success, ) = msg.sender.call{value: bal}("");
        require(success, "Transfer failed");

        emit Withdraw(msg.sender, bal);
    }

    function getBalance(address _user) external view returns (uint256) {
        return balances[_user];
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
