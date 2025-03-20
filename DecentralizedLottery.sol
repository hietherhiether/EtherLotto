// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title DecentralizedLottery
 * @dev 서버 없이 운영 가능한 분산화된 복권 시스템
 * 수수료는 특정 주소로 자동 지급되며, 블록 해시 기반 랜덤 생성 메커니즘 사용
 */
contract DecentralizedLottery {
    // 복권 관리자 주소 (수수료 수령인)
    address public constant OWNER = 0x5aff206Cb7FBb3BAb6F3D7538131D475FF2b1b5b;
    
    // 복권 상태 관리 변수
    uint256 public ticketPrice = 0.01 ether;         // 티켓 가격
    uint256 public maxTickets = 100;                // 발행할 최대 티켓 수
    uint256 public ticketsSold = 0;                 // 판매된 티켓 수
    uint256 public currentLotteryId = 1;            // 현재 복권 회차
    uint256 public feePercentage = 5;               // 수수료 퍼센트 (5%)
    
    // 복권 상태
    enum LotteryState { OPEN, CLOSED, DRAWING_WINNER }
    LotteryState public lotteryState = LotteryState.OPEN;
    
    // 티켓 구매자 정보 저장
    mapping(uint256 => address[]) public lotteryTickets;        // 복권 회차별 참여자 주소 목록
    mapping(uint256 => mapping(address => uint256)) public userTicketCount;  // 사용자별 티켓 구매 수량
    
    // 당첨자 정보 저장
    mapping(uint256 => address) public lotteryWinners;          // 복권 회차별 당첨자
    mapping(uint256 => uint256) public lotteryPrizes;           // 복권 회차별 상금
    
    // 랜덤 생성을 위한 변수
    bytes32 public lastHash;
    uint256 public lastBlockNumber;
    
    // 이벤트 정의
    event TicketPurchased(address indexed buyer, uint256 lotteryId, uint256 ticketCount);
    event WinnerSelected(uint256 indexed lotteryId, address winner, uint256 prize);
    event NewLotteryStarted(uint256 indexed lotteryId, uint256 ticketPrice, uint256 maxTickets);
    
    // 관리자만 호출 가능한 함수 제한자
    modifier onlyOwner() {
        require(msg.sender == OWNER, "Only the owner can call this function");
        _;
    }
    
    // 현재 복권이 열려있어야 하는 함수 제한자
    modifier whenLotteryOpen() {
        require(lotteryState == LotteryState.OPEN, "Lottery is not open");
        require(ticketsSold < maxTickets, "All tickets have been sold");
        _;
    }
    
    /**
     * @dev 티켓 구매 함수
     * @param _ticketCount 구매할 티켓 수량
     */
    function buyTickets(uint256 _ticketCount) external payable whenLotteryOpen {
        require(_ticketCount > 0, "Must buy at least one ticket");
        require(ticketsSold + _ticketCount <= maxTickets, "Not enough tickets left");
        require(msg.value >= ticketPrice * _ticketCount, "Insufficient payment");
        
        // 티켓 정보 저장
        for (uint256 i = 0; i < _ticketCount; i++) {
            lotteryTickets[currentLotteryId].push(msg.sender);
        }
        
        // 사용자 티켓 카운트 증가
        userTicketCount[currentLotteryId][msg.sender] += _ticketCount;
        
        // 판매된 티켓 수 증가
        ticketsSold += _ticketCount;
        
        // 이벤트 발생
        emit TicketPurchased(msg.sender, currentLotteryId, _ticketCount);
        
        // 티켓이 모두 판매되면 상태 변경
        if (ticketsSold >= maxTickets) {
            lotteryState = LotteryState.DRAWING_WINNER;
        }
    }
    
    /**
     * @dev 복권 당첨자 선정 함수
     * 블록 해시와, 블록 타임스탬프를 조합하여 의사 랜덤 숫자 생성
     */
    function drawWinner() external {
        require(lotteryState == LotteryState.DRAWING_WINNER || 
                (lotteryState == LotteryState.OPEN && ticketsSold > 0), 
                "Cannot draw winner yet or no tickets sold");
        
        lotteryState = LotteryState.CLOSED;
        
        // 지연된 랜덤성 도입을 위해 현재 블록 + 1의 해시 사용
        lastBlockNumber = block.number;
        // 당첨자는 다음 블록에서 결정됨
        
        // 이 시점에서는 아직 당첨자가 선정되지 않았으므로, 
        // revealWinner 함수를 별도로 호출해야 함
    }
    
    /**
     * @dev 당첨자 공개 함수
     * drawWinner 함수 호출 이후 다음 블록에서 호출해야 함
     */
    function revealWinner() external {
        require(lotteryState == LotteryState.CLOSED, "Lottery is not in closed state");
        require(block.number > lastBlockNumber, "Please wait for the next block");
        require(lotteryTickets[currentLotteryId].length > 0, "No tickets were sold");
        
        // 이전 블록 해시 + 현재 블록 타임스탬프로 랜덤값 생성
        bytes32 blockHash = blockhash(lastBlockNumber);
        lastHash = keccak256(abi.encodePacked(
            blockHash, 
            block.timestamp, 
            lotteryTickets[currentLotteryId].length
        ));
        
        // 랜덤 인덱스 생성
        uint256 randomIndex = uint256(lastHash) % lotteryTickets[currentLotteryId].length;
        
        // 당첨자 선정
        address winner = lotteryTickets[currentLotteryId][randomIndex];
        
        // 상금 계산 (총 티켓 판매액 - 수수료)
        uint256 totalAmount = ticketPrice * ticketsSold;
        uint256 fee = (totalAmount * feePercentage) / 100;
        uint256 prize = totalAmount - fee;
        
        // 당첨 정보 저장
        lotteryWinners[currentLotteryId] = winner;
        lotteryPrizes[currentLotteryId] = prize;
        
        // 수수료 관리자에게 전송
        (bool feeSuccess, ) = OWNER.call{value: fee}("");
        require(feeSuccess, "Fee transfer failed");
        
        // 상금 당첨자에게 전송
        (bool prizeSuccess, ) = winner.call{value: prize}("");
        require(prizeSuccess, "Prize transfer failed");
        
        // 이벤트 발생
        emit WinnerSelected(currentLotteryId, winner, prize);
        
        // 새 복권 시작
        startNewLottery();
    }
    
    /**
     * @dev 새 복권 회차 시작
     */
    function startNewLottery() private {
        currentLotteryId++;
        ticketsSold = 0;
        lotteryState = LotteryState.OPEN;
        
        emit NewLotteryStarted(currentLotteryId, ticketPrice, maxTickets);
    }
    
    /**
     * @dev 티켓 가격 변경 (관리자만 가능)
     */
    function setTicketPrice(uint256 _newPrice) external onlyOwner {
        require(_newPrice > 0, "Ticket price must be greater than 0");
        require(lotteryState == LotteryState.OPEN && ticketsSold == 0, 
                "Cannot change ticket price after tickets have been sold");
        
        ticketPrice = _newPrice;
    }
    
    /**
     * @dev 최대 티켓 수 변경 (관리자만 가능)
     */
    function setMaxTickets(uint256 _maxTickets) external onlyOwner {
        require(_maxTickets > 0, "Max tickets must be greater than 0");
        require(lotteryState == LotteryState.OPEN && ticketsSold == 0, 
                "Cannot change max tickets after tickets have been sold");
        
        maxTickets = _maxTickets;
    }
    
    /**
     * @dev 수수료 퍼센트 변경 (관리자만 가능)
     */
    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= 20, "Fee percentage cannot exceed 20%");
        require(lotteryState == LotteryState.OPEN && ticketsSold == 0, 
                "Cannot change fee percentage after tickets have been sold");
        
        feePercentage = _feePercentage;
    }
    
    /**
     * @dev 특정 복권 회차의 정보 조회
     */
    function getLotteryInfo(uint256 _lotteryId) external view returns (
        uint256 totalTickets,
        uint256 prizeAmount,
        address winner,
        bool isComplete
    ) {
        totalTickets = lotteryTickets[_lotteryId].length;
        prizeAmount = lotteryPrizes[_lotteryId];
        winner = lotteryWinners[_lotteryId];
        isComplete = (_lotteryId < currentLotteryId);
        
        return (totalTickets, prizeAmount, winner, isComplete);
    }
    
    /**
     * @dev 사용자가 보유한 티켓 수 조회
     */
    function getUserTickets(address _user) external view returns (uint256) {
        return userTicketCount[currentLotteryId][_user];
    }
    
    /**
     * @dev 현재 복권 상태 조회
     */
    function getCurrentLotteryState() external view returns (
        uint256 lotteryId,
        uint256 sold,
        uint256 max,
        uint256 price,
        LotteryState state
    ) {
        return (
            currentLotteryId,
            ticketsSold,
            maxTickets,
            ticketPrice,
            lotteryState
        );
    }
}
