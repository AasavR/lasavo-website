// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Minimal interface for ERC20 (USDC)
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

/**
 * @title LasavoUSDCPool
 * @dev Non-custodial USDC savings yield pool for blockchain natives on Monad and Coinbase Base.
 * All deposits, savings balances, and yield payouts are denominated in USDC (6 decimals).
 * Zero minimum balance hurdle, instant withdrawal, real-time APY accrual.
 */
contract LasavoUSDCPool {
    string public name = "Lasavo USDC Yield Savings Pool";
    string public symbol = "LSV-USDC";
    address public owner;

    IERC20 public immutable usdcToken;
    uint8 public immutable usdcDecimals;

    // APY in Basis Points (1480 bps = 14.8% APY)
    uint256 public apyBps = 1480;
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    struct Position {
        uint256 principal;       // In USDC (6 decimals)
        uint256 accruedYield;    // In USDC (6 decimals)
        uint256 lastUpdatedTime;
    }

    mapping(address => Position) public positions;

    uint256 public totalPoolDeposits; // Total USDC deposited
    uint256 public totalYieldPaid;    // Total USDC yield paid out
    uint256 public totalSaversCount;

    event Deposited(address indexed user, uint256 amount, uint256 timestamp);
    event Withdrawn(address indexed user, uint256 principalWithdrawn, uint256 yieldWithdrawn, uint256 timestamp);
    event YieldHarvested(address indexed user, uint256 amount, uint256 timestamp);
    event ApyUpdated(uint256 oldApy, uint256 newApy);

    modifier onlyOwner() {
        require(msg.sender == owner, "Lasavo: Only owner");
        _;
    }

    constructor(address _usdcToken) {
        owner = msg.sender;
        usdcToken = IERC20(_usdcToken);
        uint8 dec = 6;
        try IERC20(_usdcToken).decimals() returns (uint8 d) {
            dec = d;
        } catch {}
        usdcDecimals = dec;
    }

    /**
     * @notice Deposit USDC into the savings pool.
     * Can deposit any amount (even 0.10 USDC / 100,000 units).
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Lasavo: Deposit must be > 0");

        // Transfer USDC from user to this contract
        bool success = usdcToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Lasavo: USDC transfer failed");

        Position storage pos = positions[msg.sender];

        if (pos.principal == 0 && pos.accruedYield == 0) {
            totalSaversCount += 1;
        }

        // Accrue existing pending yield before principal update
        if (pos.principal > 0) {
            pos.accruedYield += calculatePendingYield(msg.sender);
        }

        pos.principal += amount;
        pos.lastUpdatedTime = block.timestamp;
        totalPoolDeposits += amount;

        emit Deposited(msg.sender, amount, block.timestamp);
    }

    /**
     * @notice Calculate pending accrued USDC yield for a saver in real time.
     */
    function calculatePendingYield(address user) public view returns (uint256) {
        Position storage pos = positions[user];
        if (pos.principal == 0 || pos.lastUpdatedTime == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - pos.lastUpdatedTime;
        // Yield = (principal * apyBps * timeElapsed) / (BPS_DENOMINATOR * SECONDS_PER_YEAR)
        return (pos.principal * apyBps * timeElapsed) / (BPS_DENOMINATOR * SECONDS_PER_YEAR);
    }

    /**
     * @notice Summary of user position in USDC.
     */
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

    /**
     * @notice Withdraw specific USDC amount (principal + yield). No lockup or penalties.
     */
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

        bool success = usdcToken.transfer(msg.sender, amount);
        require(success, "Lasavo: USDC transfer failed");

        emit Withdrawn(msg.sender, principalToWithdraw, yieldToWithdraw, block.timestamp);
    }

    /**
     * @notice Instant 100% exit - withdraws all principal and accrued USDC yield.
     */
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

        bool success = usdcToken.transfer(msg.sender, totalAvailable);
        require(success, "Lasavo: USDC transfer failed");

        emit Withdrawn(msg.sender, principalPart, yieldPart, block.timestamp);
    }

    function updateApy(uint256 newApyBps) external onlyOwner {
        require(newApyBps <= 5000, "Lasavo: Max APY 50%");
        emit ApyUpdated(apyBps, newApyBps);
        apyBps = newApyBps;
    }
}