// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PartyPayment {
    using ECDSA for bytes32;

    struct Group {
        address admin;
        bytes32 passwordHash;
        uint256 totalFund;
        uint256 userCount;
        bool active;
        mapping(address => uint256) balances;
        mapping(address => bool) joined;
        mapping(address => bool) votedCancel;
        uint256 cancelVotes;
        uint256 cancelVotesStake;
    }

    mapping(uint256 => Group) private groups;
    uint256 private groupIdCounter = 1;

    mapping(address => mapping(uint256 => bool)) private hasVoted;

    event GroupCreated(uint256 groupId, address indexed admin);
    event JoinedGroup(uint256 groupId, address indexed user);
    event FundAdded(uint256 groupId, address indexed user, uint256 amount);
    event AdminWithdraw(uint256 groupId, address indexed admin, uint256 amount);
    event UserWithdraw(uint256 groupId, address indexed user, uint256 amount);
    event CancelVote(uint256 groupId, address indexed user);
    event GroupCancelled(uint256 groupId);

    modifier onlyAdmin(uint256 groupId) {
        require(groups[groupId].admin == msg.sender, "Not group admin");
        _;
    }

    modifier groupActive(uint256 groupId) {
        require(groups[groupId].active, "Group not active");
        _;
    }

    function createGroup(bytes32 passwordHash) external returns (uint256) {
        uint256 groupId = groupIdCounter++;
        Group storage group = groups[groupId];
        group.admin = msg.sender;
        group.passwordHash = passwordHash;
        group.active = true;
        group.userCount = 1;
        group.joined[msg.sender] = true;

        emit GroupCreated(groupId, msg.sender);
        return groupId;
    }

    function joinGroup(uint256 groupId, string calldata password) external groupActive(groupId) {
        Group storage group = groups[groupId];
        require(!group.joined[msg.sender], "Already joined");
        require(group.passwordHash == keccak256(abi.encodePacked(password)), "Invalid password");

        group.joined[msg.sender] = true;
        group.userCount++;

        emit JoinedGroup(groupId, msg.sender);
    }

    function addFunds(uint256 groupId) external payable groupActive(groupId) {
        Group storage group = groups[groupId];
        require(group.joined[msg.sender], "Not a member");

        group.totalFund += msg.value;
        group.balances[msg.sender] += msg.value;

        emit FundAdded(groupId, msg.sender, msg.value);
    }

    function adminWithdraw(uint256 groupId, uint256 amount) external groupActive(groupId) onlyAdmin(groupId) {
        Group storage group = groups[groupId];
        require(address(this).balance >= amount, "Insufficient contract balance");

        group.totalFund -= amount;
        payable(msg.sender).transfer(amount);

        emit AdminWithdraw(groupId, msg.sender, amount);
    }

    function userWithdraw(uint256 groupId, uint256 amount) external groupActive(groupId) {
        Group storage group = groups[groupId];
        require(group.balances[msg.sender] >= amount, "Insufficient balance");

        group.balances[msg.sender] -= amount;
        group.totalFund -= amount;
        payable(msg.sender).transfer(amount);

        emit UserWithdraw(groupId, msg.sender, amount);
    }

    function voteCancel(uint256 groupId) external groupActive(groupId) {
        Group storage group = groups[groupId];
        require(group.joined[msg.sender], "Not a member");
        require(!hasVoted[msg.sender][groupId], "Already voted");

        group.cancelVotes++;
        group.cancelVotesStake += group.balances[msg.sender];
        hasVoted[msg.sender][groupId] = true;

        emit CancelVote(groupId, msg.sender);

        if (
            group.cancelVotes * 100 / group.userCount >= 51 ||
            group.cancelVotesStake * 100 / group.totalFund >= 51
        ) {
            group.active = false;
            emit GroupCancelled(groupId);
        }
    }

    // Security & Accessors
    function getUserBalance(uint256 groupId, address user) external view returns (uint256) {
        return groups[groupId].balances[user];
    }

    function getGroupAdmin(uint256 groupId) external view returns (address) {
        return groups[groupId].admin;
    }

    function isGroupActive(uint256 groupId) external view returns (bool) {
        return groups[groupId].active;
    }

    function hasUserJoined(uint256 groupId, address user) external view returns (bool) {
        return groups[groupId].joined[user];
    }
}
