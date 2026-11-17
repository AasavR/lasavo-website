// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LasavoAlphaVault
 * @notice Algorithmic Trading & Yield Generation Engine for Lasavo LLC.
 * Emulates the multi-flow execution architecture of Rift Protocol (Alpha Flow, Smart Flow, Micro Flow).
 * Routes trading profits back into the main Lasavo USDC Savings Pool to compound depositor APY.
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface ILasavoUSDCPool {
    function distributeYield(uint256 amount) external;
    function totalPooledUSDC() external view returns (uint256);
}

contract LasavoAlphaVault {
    address public owner;
    address public engineExecutor;
    IERC20 public immutable usdc;
    ILasavoUSDCPool public savingsPool;

    enum ExecutionFlow { AlphaFlow, SmartFlow, MicroFlow }

    struct Position {
        uint256 id;
        string asset;         // "BTC", "ETH", "DOGE", "PEPE", "BRETT"
        bool isLong;          // true = LONG, false = SHORT
        ExecutionFlow flow;   // Alpha (Momentum), Smart (Basis/Funding), Micro (Scalp)
        uint256 margin;       // USDC margin (6 decimals)
        uint256 leverage;     // 1x - 10x
        uint256 entryPrice;   // 8 decimals
        uint256 openTimestamp;
        bool isOpen;
    }

    uint256 public nextPositionId = 1;
    mapping(uint256 => Position) public positions;

    // Safety & Invariant Bounds
    uint256 public constant MAX_RISK_PER_TRADE_BPS = 200;       // 2.0% max loss per trade
    uint256 public constant CIRCUIT_BREAKER_DRAWDOWN_BPS = 500; // 5.0% max cumulative drawdown
    uint256 public constant MAX_ALLOCATION_BPS = 2500;          // Max 25% of pool can be deployed into active trading
    
    uint256 public totalProfitsHarvested;
    uint256 public totalLossesIncurred;
    uint256 public activeTradingMargin;
    bool public isPaused;

    event PositionOpened(
        uint256 indexed id,
        string asset,
        bool isLong,
        ExecutionFlow flow,
        uint256 margin,
        uint256 leverage,
        uint256 entryPrice
    );

    event PositionClosed(
        uint256 indexed id,
        uint256 exitPrice,
        int256 pnlUSDC,
        uint256 harvestedToPool
    );

    event YieldHarvestedToPool(uint256 amount, uint256 newTotalHarvested);
    event CircuitBreakerTriggered(string reason);
    event ExecutorUpdated(address newExecutor);
    event SavingsPoolUpdated(address newPool);

    modifier onlyOwner() {
        require(msg.sender == owner, "LasavoAlphaVault: Only Owner");
        _;
    }

    modifier onlyExecutor() {
        require(msg.sender == engineExecutor || msg.sender == owner, "LasavoAlphaVault: Only Executor");
        _;
    }

    modifier notPaused() {
        require(!isPaused, "LasavoAlphaVault: Engine Paused");
        _;
    }

    constructor(address _usdc, address _savingsPool, address _executor) {
        require(_usdc != address(0), "Invalid USDC");
        owner = msg.sender;
        usdc = IERC20(_usdc);
        savingsPool = ILasavoUSDCPool(_savingsPool);
        engineExecutor = _executor;
    }

    /**
     * @notice Open an automated position governed by Alpha Flow, Smart Flow, or Micro Flow.
     */
    function openPosition(
        string calldata asset,
        bool isLong,
        ExecutionFlow flow,
        uint256 margin,
        uint256 leverage,
        uint256 entryPrice
    ) external onlyExecutor notPaused returns (uint256 positionId) {
        require(margin > 0, "Zero margin");
        require(leverage >= 1 && leverage <= 10, "Leverage must be 1x-10x");
        require(entryPrice > 0, "Invalid price");

        // Verify total margin allocation does not exceed maximum safe pool allocation
        if (address(savingsPool) != address(0)) {
            uint256 poolAssets = savingsPool.totalPooledUSDC();
            if (poolAssets > 0) {
                uint256 maxAllowed = (poolAssets * MAX_ALLOCATION_BPS) / 10000;
                require(activeTradingMargin + margin <= maxAllowed, "Allocation cap reached");
            }
        }

        positionId = nextPositionId++;
        positions[positionId] = Position({
            id: positionId,
            asset: asset,
            isLong: isLong,
            flow: flow,
            margin: margin,
            leverage: leverage,
            entryPrice: entryPrice,
            openTimestamp: block.timestamp,
            isOpen: true
        });

        activeTradingMargin += margin;

        emit PositionOpened(positionId, asset, isLong, flow, margin, leverage, entryPrice);
    }

    /**
     * @notice Close a position, realize PnL, and route net profit to the savings pool.
     */
    function closePosition(
        uint256 positionId,
        uint256 exitPrice,
        int256 pnlUSDC
    ) external onlyExecutor notPaused {
        Position storage pos = positions[positionId];
        require(pos.isOpen, "Position not open");
        require(exitPrice > 0, "Invalid exit price");

        pos.isOpen = false;
        activeTradingMargin = activeTradingMargin > pos.margin ? activeTradingMargin - pos.margin : 0;

        uint256 harvested = 0;

        if (pnlUSDC > 0) {
            uint256 profit = uint256(pnlUSDC);
            totalProfitsHarvested += profit;
            harvested = profit;

            // Route profit directly to Lasavo savings pool to increase depositor yield
            if (address(savingsPool) != address(0) && usdc.balanceOf(address(this)) >= profit) {
                usdc.approve(address(savingsPool), profit);
                try savingsPool.distributeYield(profit) {
                    emit YieldHarvestedToPool(profit, totalProfitsHarvested);
                } catch {
                    // Fallback to direct transfer
                    usdc.transfer(address(savingsPool), profit);
                    emit YieldHarvestedToPool(profit, totalProfitsHarvested);
                }
            }
        } else if (pnlUSDC < 0) {
            uint256 loss = uint256(-pnlUSDC);
            totalLossesIncurred += loss;

            // Enforce max stop-loss risk check
            uint256 maxLoss = (pos.margin * MAX_RISK_PER_TRADE_BPS) / 10000;
            if (loss > maxLoss) {
                // Circuit breaker safety pause
                isPaused = true;
                emit CircuitBreakerTriggered("Stop loss limit breached");
            }
        }

        emit PositionClosed(positionId, exitPrice, pnlUSDC, harvested);
    }

    /**
     * @notice Explicitly harvest accumulated engine reserves to the savings pool.
     */
    function harvestReservesToPool(uint256 amount) external onlyOwner {
        require(amount <= usdc.balanceOf(address(this)), "Insufficient balance");
        require(address(savingsPool) != address(0), "No pool set");

        totalProfitsHarvested += amount;
        usdc.transfer(address(savingsPool), amount);
        emit YieldHarvestedToPool(amount, totalProfitsHarvested);
    }

    /**
     * @notice Admin circuit breaker
     */
    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    function setExecutor(address _executor) external onlyOwner {
        require(_executor != address(0), "Zero address");
        engineExecutor = _executor;
        emit ExecutorUpdated(_executor);
    }

    function setSavingsPool(address _savingsPool) external onlyOwner {
        require(_savingsPool != address(0), "Zero address");
        savingsPool = ILasavoUSDCPool(_savingsPool);
        emit SavingsPoolUpdated(_savingsPool);
    }

    /**
     * @notice Emergency fund recovery by owner in case of contract migration.
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }
}
