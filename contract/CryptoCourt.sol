// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title CryptoCourt
 * @dev A decentralized dispute resolution system
 * @author CryptoCourt Team
 */
contract CryptoCourt {
    
    // Struct to represent a dispute
    struct Dispute {
        uint256 id;
        address plaintiff;
        address defendant;
        string description;
        uint256 amount;
        DisputeStatus status;
        address assignedJudge;
        uint256 createdAt;
        uint256 resolvedAt;
        address winner;
    }
    
    // Enum for dispute status
    enum DisputeStatus {
        Pending,
        InProgress,
        Resolved,
        Cancelled
    }
    
    // Struct to represent a judge
    struct Judge {
        address judgeAddress;
        string name;
        uint256 reputation;
        bool isActive;
        uint256 casesHandled;
    }
    
    // State variables
    address public owner;
    uint256 public disputeCounter;
    uint256 public platformFeePercentage = 5; // 5% platform fee
    
    // Mappings
    mapping(uint256 => Dispute) public disputes;
    mapping(address => Judge) public judges;
    mapping(address => bool) public isJudge;
    mapping(uint256 => mapping(address => uint256)) public escrow; // disputeId => party => amount
    
    // Events
    event DisputeCreated(uint256 indexed disputeId, address indexed plaintiff, address indexed defendant, uint256 amount);
    event JudgeAssigned(uint256 indexed disputeId, address indexed judge);
    event DisputeResolved(uint256 indexed disputeId, address indexed winner, uint256 amount);
    event JudgeRegistered(address indexed judge, string name);
    event FundsDeposited(uint256 indexed disputeId, address indexed party, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyJudge() {
        require(isJudge[msg.sender], "Only registered judges can call this function");
        _;
    }
    
    modifier disputeExists(uint256 _disputeId) {
        require(_disputeId > 0 && _disputeId <= disputeCounter, "Dispute does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        disputeCounter = 0;
    }
    
    /**
     * @dev Core Function 1: Create a new dispute
     * @param _defendant Address of the defendant
     * @param _description Description of the dispute
     */
    function createDispute(
        address _defendant,
        string memory _description
    ) external payable {
        require(_defendant != address(0), "Invalid defendant address");
        require(_defendant != msg.sender, "Cannot create dispute with yourself");
        require(msg.value > 0, "Dispute amount must be greater than 0");
        require(bytes(_description).length > 0, "Description cannot be empty");
        
        disputeCounter++;
        
        disputes[disputeCounter] = Dispute({
            id: disputeCounter,
            plaintiff: msg.sender,
            defendant: _defendant,
            description: _description,
            amount: msg.value,
            status: DisputeStatus.Pending,
            assignedJudge: address(0),
            createdAt: block.timestamp,
            resolvedAt: 0,
            winner: address(0)
        });
        
        // Store the dispute amount in escrow
        escrow[disputeCounter][msg.sender] = msg.value;
        
        emit DisputeCreated(disputeCounter, msg.sender, _defendant, msg.value);
    }
    
    /**
     * @dev Core Function 2: Assign a judge to a dispute (only active judges can self-assign)
     * @param _disputeId ID of the dispute
     */
    function assignJudge(uint256 _disputeId) external onlyJudge disputeExists(_disputeId) {
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.status == DisputeStatus.Pending, "Dispute is not pending");
        require(dispute.assignedJudge == address(0), "Judge already assigned");
        require(judges[msg.sender].isActive, "Judge is not active");
        
        dispute.assignedJudge = msg.sender;
        dispute.status = DisputeStatus.InProgress;
        
        emit JudgeAssigned(_disputeId, msg.sender);
    }
    
    /**
     * @dev Core Function 3: Resolve a dispute (only assigned judge can resolve)
     * @param _disputeId ID of the dispute
     * @param _winner Address of the winning party
     */
    function resolveDispute(uint256 _disputeId, address _winner) external disputeExists(_disputeId) {
        Dispute storage dispute = disputes[_disputeId];
        require(msg.sender == dispute.assignedJudge, "Only assigned judge can resolve");
        require(dispute.status == DisputeStatus.InProgress, "Dispute is not in progress");
        require(_winner == dispute.plaintiff || _winner == dispute.defendant, "Winner must be plaintiff or defendant");
        
        dispute.status = DisputeStatus.Resolved;
        dispute.winner = _winner;
        dispute.resolvedAt = block.timestamp;
        
        // Calculate platform fee and winner amount
        uint256 totalAmount = escrow[_disputeId][dispute.plaintiff] + escrow[_disputeId][dispute.defendant];
        uint256 platformFee = (totalAmount * platformFeePercentage) / 100;
        uint256 winnerAmount = totalAmount - platformFee;
        
        // Transfer funds
        payable(_winner).transfer(winnerAmount);
        payable(owner).transfer(platformFee);
        
        // Update judge statistics
        judges[dispute.assignedJudge].casesHandled++;
        judges[dispute.assignedJudge].reputation += 10; // Simple reputation system
        
        // Clear escrow
        escrow[_disputeId][dispute.plaintiff] = 0;
        escrow[_disputeId][dispute.defendant] = 0;
        
        emit DisputeResolved(_disputeId, _winner, winnerAmount);
    }
    
    /**
     * @dev Register as a judge
     * @param _name Name of the judge
     */
    function registerJudge(string memory _name) external {
        require(!isJudge[msg.sender], "Already registered as judge");
        require(bytes(_name).length > 0, "Name cannot be empty");
        
        judges[msg.sender] = Judge({
            judgeAddress: msg.sender,
            name: _name,
            reputation: 100, // Starting reputation
            isActive: true,
            casesHandled: 0
        });
        
        isJudge[msg.sender] = true;
        
        emit JudgeRegistered(msg.sender, _name);
    }
    
    /**
     * @dev Defendant can deposit funds to match the dispute
     * @param _disputeId ID of the dispute
     */
    function depositDefendantFunds(uint256 _disputeId) external payable disputeExists(_disputeId) {
        Dispute storage dispute = disputes[_disputeId];
        require(msg.sender == dispute.defendant, "Only defendant can deposit");
        require(dispute.status == DisputeStatus.Pending, "Dispute is not pending");
        require(msg.value == dispute.amount, "Must match dispute amount");
        
        escrow[_disputeId][msg.sender] = msg.value;
        
        emit FundsDeposited(_disputeId, msg.sender, msg.value);
    }
    
    /**
     * @dev Get dispute details
     * @param _disputeId ID of the dispute
     */
    function getDispute(uint256 _disputeId) external view disputeExists(_disputeId) returns (
        uint256 id,
        address plaintiff,
        address defendant,
        string memory description,
        uint256 amount,
        DisputeStatus status,
        address assignedJudge,
        uint256 createdAt,
        address winner
    ) {
        Dispute memory dispute = disputes[_disputeId];
        return (
            dispute.id,
            dispute.plaintiff,
            dispute.defendant,
            dispute.description,
            dispute.amount,
            dispute.status,
            dispute.assignedJudge,
            dispute.createdAt,
            dispute.winner
        );
    }
    
    /**
     * @dev Get judge details
     * @param _judgeAddress Address of the judge
     */
    function getJudge(address _judgeAddress) external view returns (
        address judgeAddress,
        string memory name,
        uint256 reputation,
        bool isActive,
        uint256 casesHandled
    ) {
        require(isJudge[_judgeAddress], "Not a registered judge");
        Judge memory judge = judges[_judgeAddress];
        return (
            judge.judgeAddress,
            judge.name,
            judge.reputation,
            judge.isActive,
            judge.casesHandled
        );
    }
    
    /**
     * @dev Update platform fee (only owner)
     * @param _newFeePercentage New fee percentage
     */
    function updatePlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 20, "Fee cannot exceed 20%");
        platformFeePercentage = _newFeePercentage;
    }
    
    /**
     * @dev Emergency withdrawal (only owner)
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    // Fallback function to receive Ether
    receive() external payable {}
}
