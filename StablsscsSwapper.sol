pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IUSDT {
    function transfer(address, uint256) external;
    function transferFrom(address from, address to, uint256 value) external;
}

contract StablsscsSwapper is Initializable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserSwapLimitData {
        uint256 lastLimitUpdateTime;
        uint256 currentUserLimit;
    }

    struct AppConfig {
        uint256 sellStablsscsRatio;
        uint256 buyStablsscsRatio;
        uint256 userLimitUpdateIntervalUSDT;
        uint256 userLimitUpdateIntervalStablsscs;
        uint256 swapLimitUSDT;
        uint256 swapLimitStablsscs;
        uint256 baseUserLimitUSDT;
        uint256 baseUserLimitStablsscs;
        uint256 freezeDurationUSDT;
        uint256 freezeDurationStablsscs;
    }

    // ownable
    address public owner;
    address public emergencyOperator;
    address public emergencyReceiver;
    EnumerableSet.AddressSet private operators;

    // fees
    uint256 public constant FEE_DENOMINATOR = 1e6;
    uint256 public fee;

    // swap params
    address public stablsscs;
    address public usdt;
    uint256 public sellStablsscsRatio;
    uint256 public buyStablsscsRatio;
    uint256 public constant ratioDenominator = 1e6;
    uint256 public userLimitUpdateIntervalUSDT;
    uint256 public userLimitUpdateIntervalStablsscs;
    uint256 public swapLimitUSDT;
    uint256 public swapLimitStablsscs;
    uint256 public baseUserLimitUSDT; // in USDT
    uint256 public baseUserLimitStablsscs; // in Stablsscs
    uint256 public freezeDurationUSDT; // in seconds
    uint256 public freezeDurationStablsscs; // in seconds

    mapping(address => UserSwapLimitData) public userSwapLimitUSDT;
    mapping(address => UserSwapLimitData) public userSwapLimitStablsscs;
    mapping(address => uint256) public userSwapFreezeUSDT;
    mapping(address => uint256) public userSwapFreezeStablsscs;

    // pausable
    bool public paused = false;

    // events
    event OwnerChanged(address indexed newOwner);
    event OperatorAdded(address indexed newOperator);
    event OperatorRemoved(address indexed removedOperator);
    event EmergencyOperatorChanged(address indexed newEmergencyOperator);
    event EmergencyReceiverChanged(address indexed newEmergencyReceiver);
    event UserLimitUpdateIntervalUSDTUpdated(uint256 newInterval);
    event UserLimitUpdateIntervalStablsscsUpdated(uint256 newInterval);
    event Paused(bool paused);
    event SellStablsscsRatioUpdated(uint256 newRatio);
    event BuyStablsscsRatioUpdated(uint256 newRatio);
    event SwapLimitUSDTUpdated(uint256 newLimit);
    event SwapLimitStablsscsUpdated(uint256 newLimit);
    event BaseUserLimitUSDTUpdated(uint256 newLimit);
    event BaseUserLimitStablsscsUpdated(uint256 newLimit);
    event FreezeDurationUSDTUpdated(uint256 newDuration);
    event FreezeDurationStablsscsUpdated(uint256 newDuration);
    event FeeUpdated(uint256 fee);
    event Exchange(
        address indexed tokenFrom,
        address indexed tokenTo,
        uint256 amountIn,
        uint256 amountOut,
        uint256 feeRatio,
        uint256 exchangeRate
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyOwnerOrOperator() {
        require(operators.contains(msg.sender) || msg.sender == owner, "not owner or operator");
        _;
    }

    modifier onlyOwnerOrOperatorOrEmergencyOperator() {
        require(operators.contains(msg.sender) || msg.sender == owner || msg.sender == emergencyOperator, "not owner or operator or emergency operator");
        _;
    }

    modifier whenNotPaused() {
        require(paused == false, "protocol paused");
        _;
    }

    function initialize(
        address _owner,
        address[] memory _operators,
        address _stablsscs,
        address _usdt,
        address _emergencyOperator,
        address _emergencyReceiver,
        AppConfig memory _appConfig
    ) public payable initializer {
        require(_owner != address(0), "Owner should be non zero address");
        require(_stablsscs != address(0), "Stablsscs should be non zero address");
        require(_usdt != address(0), "USDT should be non zero address");
        require(_emergencyOperator != address(0), "emergency operator should be non zero address");
        require(_emergencyReceiver != address(0), "emergency receiver should be non zero address");
        owner = _owner;
        for (uint256 i = 0; i < _operators.length; i++) {
            require(_operators[i] != address(0), "operator should be non zero address");
            require(operators.add(_operators[i]), "operator already exists");
        }
        stablsscs = _stablsscs;
        usdt = _usdt;
        emergencyOperator = _emergencyOperator;
        emergencyReceiver = _emergencyReceiver;
        sellStablsscsRatio = _appConfig.sellStablsscsRatio;
        buyStablsscsRatio = _appConfig.buyStablsscsRatio;
        baseUserLimitUSDT = _appConfig.baseUserLimitUSDT;
        baseUserLimitStablsscs = _appConfig.baseUserLimitStablsscs;
        freezeDurationUSDT = _appConfig.freezeDurationUSDT;
        freezeDurationStablsscs = _appConfig.freezeDurationStablsscs;
        userLimitUpdateIntervalUSDT = _appConfig.userLimitUpdateIntervalUSDT;
        userLimitUpdateIntervalStablsscs = _appConfig.userLimitUpdateIntervalStablsscs;
        swapLimitUSDT = _appConfig.swapLimitUSDT;
        swapLimitStablsscs = _appConfig.swapLimitStablsscs;
    }

    function getOperators() external view returns (address[] memory) {
        return operators.values();
    }

    function getOperatorsCount() external view returns (uint256) {
        return operators.length();
    }

    function updateOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "owner cannot be zero address");
        owner = newOwner;
        emit OwnerChanged(newOwner);
    }

    function addOperator(address newOperator) external onlyOwner {
        require(newOperator != address(0), "operator cannot be zero address");
        require(operators.add(newOperator), "operator already exists");
        emit OperatorAdded(newOperator);
    }

    function removeOperator(address operator) external onlyOwner {
        require(operators.contains(operator), "operator does not exist");
        operators.remove(operator);
        emit OperatorRemoved(operator);
    }

    function updateEmergencyOperator(address newEmergencyOperator) external onlyOwner {
        require(newEmergencyOperator != address(0), "emergency operator cannot be zero address");
        emergencyOperator = newEmergencyOperator;
        emit EmergencyOperatorChanged(newEmergencyOperator);
    }

    function updateEmergencyReceiver(address newEmergencyReceiver) external onlyOwner {
        require(newEmergencyReceiver != address(0), "emergency receiver cannot be zero address");
        emergencyReceiver = newEmergencyReceiver;
        emit EmergencyReceiverChanged(newEmergencyReceiver);
    }

    function updateUserLimitUpdateIntervalUSDT(uint256 newInterval) external onlyOwnerOrOperator {
        userLimitUpdateIntervalUSDT = newInterval;
        emit UserLimitUpdateIntervalUSDTUpdated(newInterval);
    }

    function updateUserLimitUpdateIntervalStablsscs(uint256 newInterval) external onlyOwnerOrOperator {
        userLimitUpdateIntervalStablsscs = newInterval;
        emit UserLimitUpdateIntervalStablsscsUpdated(newInterval);
    }

    function pause() external onlyOwnerOrOperator whenNotPaused {
        paused = true;
        emit Paused(paused);
    }

    function unpause() external onlyOwnerOrOperator {
        paused = false;
        emit Paused(paused);
    }

    function supplyUSDT(uint256 amount) external {
        require(amount > 0, "supply amount cannot be zero");
        IUSDT(usdt).transferFrom(msg.sender, address(this), amount);
    }

    function supplyStablsscs(uint256 amount) external {
        require(amount > 0, "supply amount cannot be zero");
        IERC20(stablsscs).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawUSDT(uint256 amount) external onlyOwnerOrOperator {
        require(amount > 0, "withdraw amount cannot be zero");
        IUSDT(usdt).transfer(msg.sender, amount);
    }

    function withdrawStablsscs(uint256 amount) external onlyOwnerOrOperator {
        require(amount > 0, "withdraw amount cannot be zero");
        IERC20(stablsscs).safeTransfer(msg.sender, amount);
    }

    function setSellStablsscsRatio(uint256 newRatio) external onlyOwnerOrOperator {
        require(newRatio > 0, "sell ratio cannot be 0");
        sellStablsscsRatio = newRatio;
        emit SellStablsscsRatioUpdated(newRatio);
    }

    function setSwapLimitUSDT(uint256 newLimit) external onlyOwnerOrOperator {
        swapLimitUSDT = newLimit;
        emit SwapLimitUSDTUpdated(newLimit);
    }

    function setSwapLimitStablsscs(uint256 newLimit) external onlyOwnerOrOperator {
        swapLimitStablsscs = newLimit;
        emit SwapLimitStablsscsUpdated(newLimit);
    }

    function setBaseUserLimitUSDT(uint256 newLimit) external onlyOwnerOrOperator {
        baseUserLimitUSDT = newLimit;
        emit BaseUserLimitUSDTUpdated(newLimit);
    }

    function setBaseUserLimitStablsscs(uint256 newLimit) external onlyOwnerOrOperator {
        baseUserLimitStablsscs = newLimit;
        emit BaseUserLimitStablsscsUpdated(newLimit);
    }

    function setFreezeDurationUSDT(uint256 newDuration) external onlyOwnerOrOperator {
        freezeDurationUSDT = newDuration;
        emit FreezeDurationUSDTUpdated(newDuration);
    }

    function setFreezeDurationStablsscs(uint256 newDuration) external onlyOwnerOrOperator {
        freezeDurationStablsscs = newDuration;
        emit FreezeDurationStablsscsUpdated(newDuration);
    }

    function setBuyStablsscsRatio(uint256 newRatio) external onlyOwnerOrOperator {
        require(newRatio > 0, "buy ratio cannot be 0");
        buyStablsscsRatio = newRatio;
        emit BuyStablsscsRatioUpdated(newRatio);
    }

    function setFee(uint256 newFee) external onlyOwnerOrOperator {
        require(newFee < FEE_DENOMINATOR);
        fee = newFee;
        emit FeeUpdated(newFee);
    }

    function _refreshUserDailyLimitsUSDT(address user, uint256 amount) internal {
        require(user != address(0), "user cannot be zero address");
        if (userSwapLimitUSDT[user].lastLimitUpdateTime + userLimitUpdateIntervalUSDT < block.timestamp) {
            userSwapLimitUSDT[user].currentUserLimit = baseUserLimitUSDT;
            userSwapLimitUSDT[user].lastLimitUpdateTime = block.timestamp;
        }
        require(userSwapLimitUSDT[user].currentUserLimit >= amount, "user USDT limit exceeded");
        userSwapLimitUSDT[user].currentUserLimit -= amount;
    }

    function _refreshUserDailyLimitsStablsscs(address user, uint256 amount) internal {
        require(user != address(0), "user cannot be zero address");
        if (userSwapLimitStablsscs[user].lastLimitUpdateTime + userLimitUpdateIntervalStablsscs < block.timestamp) {
            userSwapLimitStablsscs[user].currentUserLimit = baseUserLimitStablsscs;
            userSwapLimitStablsscs[user].lastLimitUpdateTime = block.timestamp;
        }
        require(userSwapLimitStablsscs[user].currentUserLimit >= amount, "user Stablsscs limit exceeded");
        userSwapLimitStablsscs[user].currentUserLimit -= amount;
    }

    function _validateSwapToUSDT(uint256 amount) internal {
        require(userSwapFreezeUSDT[msg.sender] + freezeDurationUSDT < block.timestamp, "swap to USDT is frozen");
        userSwapFreezeUSDT[msg.sender] = block.timestamp;
        if (msg.sender != tx.origin) {
            require(userSwapFreezeUSDT[tx.origin] + freezeDurationUSDT < block.timestamp, "swap to USDT is frozen");
            userSwapFreezeUSDT[tx.origin] = block.timestamp;
        }

        require(swapLimitUSDT == 0 || swapLimitUSDT >= amount, "swap limit for one tx to USDT exceeded");
        require(IERC20(usdt).balanceOf(address(this)) >= amount, "not enough tokens for swap");

        _refreshUserDailyLimitsUSDT(msg.sender, amount);

        if (msg.sender != tx.origin) {
            _refreshUserDailyLimitsUSDT(tx.origin, amount);
        }
    }

    function _validateSwapToStablsscs(uint256 amount) internal {
        require(userSwapFreezeStablsscs[msg.sender] + freezeDurationStablsscs < block.timestamp, "swap to Stablsscs is frozen");
        userSwapFreezeStablsscs[msg.sender] = block.timestamp;
        if (msg.sender != tx.origin) {
            require(userSwapFreezeStablsscs[tx.origin] + freezeDurationStablsscs < block.timestamp, "swap to Stablsscs is frozen");
            userSwapFreezeStablsscs[tx.origin] = block.timestamp;
        }

        require(swapLimitStablsscs == 0 || swapLimitStablsscs >= amount, "swap limit for one tx to Stablsscs exceeded");
        require(IERC20(stablsscs).balanceOf(address(this)) >= amount, "not enough tokens for swap");

        _refreshUserDailyLimitsStablsscs(msg.sender, amount);

        if (msg.sender != tx.origin) {
            _refreshUserDailyLimitsStablsscs(tx.origin, amount);
        }
    }

    function exchangeStablsscsToUSDT(uint256 stablsscsAmount) external whenNotPaused {
        require(stablsscsAmount > 0, "exchange amount cannot be zero");

        uint256 amountWithoutFee = stablsscsAmount * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;
        uint256 usdtAmount = amountWithoutFee * sellStablsscsRatio / ratioDenominator;

        _validateSwapToUSDT(usdtAmount);

        IERC20(stablsscs).safeTransferFrom(msg.sender, address(this), stablsscsAmount);
        IUSDT(usdt).transfer(msg.sender, usdtAmount);
        emit Exchange(
            stablsscs,
            usdt,
            stablsscsAmount,
            usdtAmount,
            fee,
            sellStablsscsRatio
        );
    }

    function exchangeUSDTToStablsscs(uint256 usdtAmount) external whenNotPaused {
        require(usdtAmount > 0, "exchange amount cannot be zero");
        uint256 amountWithoutFee = usdtAmount * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;
        uint256 stablsscsAmount = amountWithoutFee * buyStablsscsRatio / ratioDenominator;

        _validateSwapToStablsscs(stablsscsAmount);

        IUSDT(usdt).transferFrom(msg.sender, address(this), usdtAmount);
        IERC20(stablsscs).safeTransfer(msg.sender, stablsscsAmount);
        emit Exchange(
            usdt,
            stablsscs,
            usdtAmount,
            stablsscsAmount,
            fee,
            buyStablsscsRatio
        );
    }

    function emergencyExit() external onlyOwnerOrOperatorOrEmergencyOperator {
        IUSDT(usdt).transfer(emergencyReceiver, IERC20(usdt).balanceOf(address(this)));
    }
}