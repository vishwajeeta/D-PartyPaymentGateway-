// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

contract PartyPaymentDAO {
    struct Group {
        address admin;
        bytes32 passwordHash;
        bool isActive;
        uint totalBalance;
        uint voteCount;
        uint unlockThreshold;
        mapping(address => bool) members;
        mapping(address => uint) balances;
        mapping(address => bool) votedToUnlock;
    }

    uint public groupCount;
    mapping(uint => Group) public groups;

    modifier onlyAdmin(uint groupId) {
        require(msg.sender == groups[groupId].admin, "Not admin");
        _;
    }

    modifier onlyMember(uint groupId) {
        require(groups[groupId].members[msg.sender], "Not a member");
        _;
    }

    function createGroup(bytes32 passwordHash) external returns (uint groupId) {
        groupId = groupCount++;
        Group storage g = groups[groupId];
        g.admin = msg.sender;
        g.passwordHash = passwordHash;
        g.isActive = true;
        g.unlockThreshold = 51;
        g.members[msg.sender] = true;
    }

    function joinGroup(uint groupId, string memory password) external {
        Group storage g = groups[groupId];
        require(g.isActive, "Inactive group");
        require(!g.members[msg.sender], "Already joined");
        require(g.passwordHash == keccak256(abi.encodePacked(password)), "Wrong password");
        g.members[msg.sender] = true;
    }

    function deposit(uint groupId) external payable onlyMember(groupId) {
        Group storage g = groups[groupId];
        require(g.isActive, "Inactive group");
        g.balances[msg.sender] += msg.value;
        g.totalBalance += msg.value;
    }

    function withdrawOwn(uint groupId, uint amount) external onlyMember(groupId) {
        Group storage g = groups[groupId];
        require(g.balances[msg.sender] >= amount, "Insufficient balance");
        g.balances[msg.sender] -= amount;
        g.totalBalance -= amount;
        payable(msg.sender).transfer(amount);
    }

    function adminWithdraw(uint groupId, uint amount) external onlyAdmin(groupId) {
        Group storage g = groups[groupId];
        require(g.totalBalance >= amount, "Insufficient pool");
        require(amount <= g.totalBalance / 5, "Exceeds 20% limit");
        g.totalBalance -= amount;
        payable(msg.sender).transfer(amount);
    }

    function voteToUnlock(uint groupId) external onlyMember(groupId) {
        Group storage g = groups[groupId];
        require(!g.votedToUnlock[msg.sender], "Already voted");
        g.votedToUnlock[msg.sender] = true;
        g.voteCount++;

        if ((g.voteCount * 100) / countMembers(groupId) >= g.unlockThreshold) {
            g.isActive = false;
            distributeFunds(groupId);
        }
    }

    function countMembers(uint groupId) public view returns (uint count) {
        Group storage g = groups[groupId];
        for (uint i = 0; i < groupCount; i++) {
            if (g.members[address(uint160(i))]) count++;
        }
    }

    function distributeFunds(uint groupId) internal {
        Group storage g = groups[groupId];
        for (uint i = 0; i < groupCount; i++) {
            address user = address(uint160(i));
            if (g.members[user] && g.balances[user] > 0) {
                uint amt = g.balances[user];
                g.balances[user] = 0;
                payable(user).transfer(amt);
            }
        }
        g.totalBalance = 0;
    }
}
