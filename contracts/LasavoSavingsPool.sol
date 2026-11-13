// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LasavoSavingsPool {
    string public name = "Lasavo Yield Savings Pool";
    string public symbol = "LSV-POOL";
    address public owner;
    uint256 public apyBps = 1480; 
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    struct Position {
        uint256 principal;
        uint256 accruedYield;
        uint256 lastUpdatedTime;
    }

    mapping(address => Position) public positions;
    uint256 public totalPoolDeposits;
    uint256 public totalYieldPaid;
    uint256 public totalSaversCount;

    event Deposited(address indexed user, uint256 amount, uint256 timestamp);
    event Withdrawn(address indexed user, uint256 principalWithdrawn, uint256 yieldWithdrawn, uint256 timestamp);
    event YieldHarvested(address indexed user, uint256 yieldAmount, uint256 timestamp);

    constructor() {
        owner = msg.sender;
    }

    function deposit() external payable {
        require(msg.value > 0, "Lasavo: Must deposit > 0");
        Position storage pos = positions[msg.sender];

        if (pos.principal == 0 && pos.accruedYield == 0) {
            totalSaversCount += 1;
        }

        if (pos.principal > 0) {
            pos.accruedYield += calculatePendingYield(msg.sender);
        }

        pos.principal += msg.value;
        pos.lastUpdatedTime = block.timestamp;
        totalPoolDeposits += msg.value;

        emit Deposited(msg.sender, msg.value, block.timestamp);
    }

    function calculatePendingYield(address user) public view returns (uint256) {
        Position storage pos = positions[user];
        if (pos.principal == 0 || pos.lastUpdatedTime == 0) {
            return 0;
        }
        uint256 timeElapsed = block.timestamp - pos.lastUpdatedTime;
        return (pos.principal * apyBps * timeElapsed) / (BPS_DENOMINATOR * SECONDS_PER_YEAR);
    }

    function getAccountSummary(address user) external view returns (
        uint256 principal,
        uint256 totalYield,
        uint256 totalBalance,
        uint256 currentApy
    ) {
        Position storage pos = positions[user];
        principal = pos.principal;
        totalYield = pos.accruedYield + calculatePendingYield(user);
        totalBalance = principal + totalYield;
        currentApy = apyBps;
    }

    function withdraw(uint256 amount) external {
        Position storage pos = positions[msg.sender];
        uint256 pending = calculatePendingYield(msg.sender);
        uint256 totalAvailableYield = pos.accruedYield + pending;
        uint256 totalAvailable = pos.principal + totalAvailableYield;

        require(totalAvailable > 0, "Lasavo: Zero balance");
        require(amount <= totalAvailable, "Lasavo: Exceeds total savings");

        uint256 yieldToWithdraw = 0;
        uint256 principalToWithdraw = 0;

        if (amount <= totalAvailableYield) {
            yieldToWithdraw = amount;
            pos.accruedYield = totalAvailableYield - amount;
        } else {
            yieldToWithdraw = totalAvailableYield;
            pos.accruedYield = 0;
            principalToWithdraw = amount - yieldToWithdraw;
            pos.principal -= principalToWithdraw;
            totalPoolDeposits -= principalToWithdraw;
        }

        pos.lastUpdatedTime = block.timestamp;
        totalYieldPaid += yieldToWithdraw;

        if (pos.principal == 0 && pos.accruedYield == 0 && totalSaversCount > 0) {
            totalSaversCount -= 1;
        }

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Lasavo: Transfer failed");

        emit Withdrawn(msg.sender, principalToWithdraw, yieldToWithdraw, block.timestamp);
    }

    function withdrawAll() external {
        Position storage pos = positions[msg.sender];
        uint256 pending = calculatePendingYield(msg.sender);
        uint256 totalAvailable = pos.principal + pos.accruedYield + pending;
        require(totalAvailable > 0, "Lasavo: Zero balance");

        uint256 yieldPart = pos.accruedYield + pending;
        uint256 principalPart = pos.principal;

        totalPoolDeposits -= principalPart;
        totalYieldPaid += yieldPart;

        delete positions[msg.sender];
        if (totalSaversCount > 0) totalSaversCount -= 1;

        (bool success, ) = payable(msg.sender).call{value: totalAvailable}("");
        require(success, "Lasavo: Transfer failed");

        emit Withdrawn(msg.sender, principalPart, yieldPart, block.timestamp);
    }

    receive() external payable {}
}