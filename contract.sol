// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Decentralized Quiz Competition
 * @dev A blockchain-based quiz competition with tokenized rewards
 */
contract DecentralizedQuizCompetition is Ownable, ReentrancyGuard {
    IERC20 public rewardToken;
    
    struct Quiz {
        uint256 id;
        string title;
        string description;
        uint256 entryFee;
        uint256 rewardPool;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        mapping(address => bool) participants;
        mapping(address => uint256) scores;
        address[] participantList;
    }
    
    struct Question {
        uint256 id;
        uint256 quizId;
        string questionText;
        string[] options;
        uint8 correctOptionIndex;
        uint256 points;
    }
    
    mapping(uint256 => Quiz) public quizzes;
    mapping(uint256 => Question[]) public quizQuestions;
    mapping(address => uint256) public userTokenBalance;
    
    uint256 public quizCount;
    uint256 public platformFeePercentage = 5; // 5% fee
    
    event QuizCreated(uint256 indexed quizId, string title, uint256 startTime, uint256 endTime);
    event QuizJoined(uint256 indexed quizId, address indexed participant);
    event QuizCompleted(uint256 indexed quizId, address indexed participant, uint256 score);
    event RewardDistributed(uint256 indexed quizId, address indexed participant, uint256 amount);
    
    /**
     * @dev Constructor for the Decentralized Quiz Competition contract
     * @param _rewardToken Address of the ERC20 token used for rewards
     */
    constructor(address _rewardToken) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
    }
    
    /**
     * @dev Creates a new quiz
     * @param _title Title of the quiz
     * @param _description Description of the quiz
     * @param _entryFee Entry fee for the quiz (in wei)
     * @param _startTime Start time of the quiz (unix timestamp)
     * @param _endTime End time of the quiz (unix timestamp)
     * @return quizId ID of the created quiz
     */
    function createQuiz(
        string memory _title,
        string memory _description,
        uint256 _entryFee,
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner returns (uint256) {
        require(_startTime > block.timestamp, "Start time must be in the future");
        require(_endTime > _startTime, "End time must be after start time");
        
        uint256 quizId = quizCount++;
        Quiz storage newQuiz = quizzes[quizId];
        newQuiz.id = quizId;
        newQuiz.title = _title;
        newQuiz.description = _description;
        newQuiz.entryFee = _entryFee;
        newQuiz.startTime = _startTime;
        newQuiz.endTime = _endTime;
        newQuiz.isActive = true;
        
        emit QuizCreated(quizId, _title, _startTime, _endTime);
        return quizId;
    }
    
    /**
     * @dev Adds questions to a quiz
     * @param _quizId ID of the quiz
     * @param _questionTexts Array of question texts
     * @param _options Array of options for each question
     * @param _correctOptionIndices Array of correct option indices
     * @param _points Array of points for each question
     */
    function addQuestions(
        uint256 _quizId,
        string[] memory _questionTexts,
        string[][] memory _options,
        uint8[] memory _correctOptionIndices,
        uint256[] memory _points
    ) external onlyOwner {
        require(_questionTexts.length == _options.length, "Input arrays must have the same length");
        require(_questionTexts.length == _correctOptionIndices.length, "Input arrays must have the same length");
        require(_questionTexts.length == _points.length, "Input arrays must have the same length");
        
        for (uint256 i = 0; i < _questionTexts.length; i++) {
            Question memory newQuestion = Question({
                id: quizQuestions[_quizId].length,
                quizId: _quizId,
                questionText: _questionTexts[i],
                options: _options[i],
                correctOptionIndex: _correctOptionIndices[i],
                points: _points[i]
            });
            
            quizQuestions[_quizId].push(newQuestion);
        }
    }
    
    /**
     * @dev Allows a user to join a quiz by paying the entry fee
     * @param _quizId ID of the quiz to join
     */
    function joinQuiz(uint256 _quizId) external payable nonReentrant {
        Quiz storage quiz = quizzes[_quizId];
        
        require(quiz.isActive, "Quiz is not active");
        require(block.timestamp >= quiz.startTime, "Quiz has not started yet");
        require(block.timestamp <= quiz.endTime, "Quiz has ended");
        require(!quiz.participants[msg.sender], "Already joined this quiz");
        require(msg.value == quiz.entryFee, "Incorrect entry fee");
        
        quiz.participants[msg.sender] = true;
        quiz.participantList.push(msg.sender);
        quiz.rewardPool += msg.value;
        
        emit QuizJoined(_quizId, msg.sender);
    }
    
    /**
     * @dev Submits answers for a quiz
     * @param _quizId ID of the quiz
     * @param _answers Array of answers (option indices)
     */
    function submitAnswers(uint256 _quizId, uint8[] memory _answers) external nonReentrant {
        Quiz storage quiz = quizzes[_quizId];
        
        require(quiz.isActive, "Quiz is not active");
        require(block.timestamp >= quiz.startTime, "Quiz has not started yet");
        require(block.timestamp <= quiz.endTime, "Quiz has ended");
        require(quiz.participants[msg.sender], "Not a participant of this quiz");
        require(_answers.length == quizQuestions[_quizId].length, "Invalid number of answers");
        
        uint256 score = 0;
        for (uint256 i = 0; i < _answers.length; i++) {
            if (_answers[i] == quizQuestions[_quizId][i].correctOptionIndex) {
                score += quizQuestions[_quizId][i].points;
            }
        }
        
        quiz.scores[msg.sender] = score;
        
        emit QuizCompleted(_quizId, msg.sender, score);
    }
    
    /**
     * @dev Distributes rewards for a completed quiz
     * @param _quizId ID of the quiz
     */
    function distributeRewards(uint256 _quizId) external onlyOwner nonReentrant {
        Quiz storage quiz = quizzes[_quizId];
        
        require(quiz.isActive, "Quiz is not active");
        require(block.timestamp > quiz.endTime, "Quiz has not ended yet");
        
        uint256 platformFee = (quiz.rewardPool * platformFeePercentage) / 100;
        uint256 rewardPool = quiz.rewardPool - platformFee;
        
        uint256 totalScore = 0;
        for (uint256 i = 0; i < quiz.participantList.length; i++) {
            address participant = quiz.participantList[i];
            totalScore += quiz.scores[participant];
        }
        
        if (totalScore > 0) {
            for (uint256 i = 0; i < quiz.participantList.length; i++) {
                address participant = quiz.participantList[i];
                uint256 score = quiz.scores[participant];
                
                if (score > 0) {
                    uint256 reward = (rewardPool * score) / totalScore;
                    userTokenBalance[participant] += reward;
                    
                    emit RewardDistributed(_quizId, participant, reward);
                }
            }
        }
        
        quiz.isActive = false;
        quiz.rewardPool = 0;
        
        // Transfer platform fee to owner
        payable(owner()).transfer(platformFee);
    }
    
    /**
     * @dev Allows users to withdraw their earned tokens
     */
    function withdrawTokens() external nonReentrant {
        uint256 amount = userTokenBalance[msg.sender];
        require(amount > 0, "No tokens to withdraw");
        
        userTokenBalance[msg.sender] = 0;
        rewardToken.transfer(msg.sender, amount);
    }
    
    /**
     * @dev Sets the platform fee percentage
     * @param _percentage New platform fee percentage
     */
    function setPlatformFeePercentage(uint256 _percentage) external onlyOwner {
        require(_percentage <= 20, "Fee percentage too high");
        platformFeePercentage = _percentage;
    }
    
    /**
     * @dev Sets the reward token address
     * @param _rewardToken New reward token address
     */
    function setRewardToken(address _rewardToken) external onlyOwner {
        rewardToken = IERC20(_rewardToken);
    }
    
    /**
     * @dev Gets the number of participants in a quiz
     * @param _quizId ID of the quiz
     * @return Number of participants
     */
    function getParticipantCount(uint256 _quizId) external view returns (uint256) {
        return quizzes[_quizId].participantList.length;
    }
    
    /**
     * @dev Gets the score of a participant in a quiz
     * @param _quizId ID of the quiz
     * @param _participant Address of the participant
     * @return Score of the participant
     */
    function getParticipantScore(uint256 _quizId, address _participant) external view returns (uint256) {
        return quizzes[_quizId].scores[_participant];
    }
    
    /**
     * @dev Gets the number of questions in a quiz
     * @param _quizId ID of the quiz
     * @return Number of questions
     */
    function getQuestionCount(uint256 _quizId) external view returns (uint256) {
        return quizQuestions[_quizId].length;
    }
}
