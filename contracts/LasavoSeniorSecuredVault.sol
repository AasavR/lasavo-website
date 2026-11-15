// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

/**
 * @title LasavoSeniorSecuredVault
 * @notice ERC-4626 style Risk-Tranched Senior Secured Debt Facility ($5.0M)
 * @dev Legal Entity: Lasavo LLC (New Mexico, USA, UCC-1 Perfected)
 * Tranche Waterfall:
 *  - Senior Lenders (85% net fees + SOFR + 450 bps floor, projected 14-22% APY)
 *  - First-Loss Junior Reserve: 7.5% ($375,000 USDC) funded by Lasavo LLC
 *  - Operational Reserve: 7.5%
 */
contract LasavoSeniorSecuredVault {
    string public name = "Lasavo Senior Secured USDC Vault";
    string public symbol = "sLSV-USDC";
    
    address public immutable owner;
    IERC20 public immutable usdc;

    uint256 public constant FACILITY_CAP = 5_000_000 * 1e6; // $5.0M USDC
    uint256 public constant JUNIOR_BUFFER_BPS = 750; // 7.5% first-loss protection
    uint256 public constant SENIOR_APY_BPS = 1680; // 16.8% base target APY
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    uint256 public totalSeniorDeposited;
    uint256 public juniorFirstLossBuffer; // Lasavo funded buffer

    struct SeniorPosition {
        uint256 principal;
        uint256 accruedYield;
        uint256 depositTimestamp;
        uint256 lockDuration; // e.g. 90 days or 180 days
    }

    mapping(address => SeniorPosition) public seniorPositions;
    mapping(address => bool) public institutionalAllowlist;

    event SeniorDeposit(address indexed allocator, uint256 amount, uint256 lockDuration);
    event SeniorWithdraw(address indexed allocator, uint256 principal, uint256 yieldPaid);
    event JuniorBufferFunded(uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Lasavo: Only governance/owner");
        _;
    }

    constructor(address _usdc) {
        owner = msg.sender;
        usdc = IERC20(_usdc);
    }

    function setInstitutionalAllowlist(address allocator, bool allowed) external onlyOwner {
        institutionalAllowlist[allocator] = allowed;
    }

    function fundJuniorFirstLoss(uint256 amount) external onlyOwner {
        require(usdc.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        juniorFirstLossBuffer += amount;
        emit JuniorBufferFunded(amount);
    }

    function depositSenior(uint256 amount, uint256 lockDays) external {
        require(institutionalAllowlist[msg.sender] || msg.sender == owner, "Lasavo: KYC/Allowlist required for Senior Vault");
        require(totalSeniorDeposited + amount <= FACILITY_CAP, "Lasavo: Exceeds $5M Facility Cap");
        require(lockDays >= 90, "Lasavo: Minimum 90-day institutional lock");

        require(usdc.transferFrom(msg.sender, address(this), amount), "USDC transfer failed");

        SeniorPosition storage pos = seniorPositions[msg.sender];
        if (pos.principal > 0) {
            pos.accruedYield += calculateYield(msg.sender);
        }
        pos.principal += amount;
        pos.depositTimestamp = block.timestamp;
        pos.lockDuration = lockDays * 1 days;
        totalSeniorDeposited += amount;

        emit SeniorDeposit(msg.sender, amount, pos.lockDuration);
    }

    function calculateYield(address allocator) public view returns (uint256) {
        SeniorPosition storage pos = seniorPositions[allocator];
        if (pos.principal == 0) return 0;
        uint256 duration = block.timestamp - pos.depositTimestamp;
        return (pos.principal * SENIOR_APY_BPS * duration) / (BPS_DENOMINATOR * SECONDS_PER_YEAR);
    }
}