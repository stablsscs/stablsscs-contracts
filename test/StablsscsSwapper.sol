// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StablsscsSwapper} from "../src/StablsscsSwapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Mock USDT contract for testing
contract MockUSDT {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }
}

// Mock Stablsscs token contract for testing
contract MockStablsscs {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }
}

contract StablsscsSwapperTest is Test {
    StablsscsSwapper public swapper;
    StablsscsSwapper public swapperImplementation;
    TransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;
    MockUSDT public usdt;
    MockStablsscs public stablsscs;

    // Event declarations for testing
    event UserLimitUpdateIntervalUSDTUpdated(uint256 newInterval);
    event UserLimitUpdateIntervalStablsscsUpdated(uint256 newInterval);
    event OperatorAdded(address indexed newOperator);
    event OperatorRemoved(address indexed removedOperator);

    address public owner = address(0x123);
    address public operator = address(0x124);
    address public emergencyOperator = address(0x127);
    address public emergencyReceiver = address(0x128);
    address public user1 = address(0x125);
    address public user2 = address(0x126);
    address public proxyAdminOwner = address(0x123);

    uint256 public constant SELL_RATIO = 1000000; // 1:1 ratio
    uint256 public constant BUY_RATIO = 1000000;  // 1:1 ratio
    uint256 public constant BASE_USER_LIMIT = 1000 * 1e6; // 1000 USDT
    uint256 public constant FREEZE_DURATION = 3600; // 1 hour
    uint256 public constant FEE = 50000; // 5% fee

    function setUp() public {
        // Set specific timestamp for tests
        vm.warp(1753705949);

        usdt = new MockUSDT();
        stablsscs = new MockStablsscs();

        // Create operators array
        address[] memory operators = new address[](1);
        operators[0] = operator;

        // Create AppConfig struct
        StablsscsSwapper.AppConfig memory appConfig = StablsscsSwapper.AppConfig({
            sellStablsscsRatio: SELL_RATIO,
            buyStablsscsRatio: BUY_RATIO,
            userLimitUpdateIntervalUSDT: 1 days,
            userLimitUpdateIntervalStablsscs: 1 days,
            swapLimitUSDT: 0,
            swapLimitStablsscs: 0,
            baseUserLimitUSDT: BASE_USER_LIMIT,
            baseUserLimitStablsscs: BASE_USER_LIMIT,
            freezeDurationUSDT: FREEZE_DURATION,
            freezeDurationStablsscs: FREEZE_DURATION
        });

        swapperImplementation = new StablsscsSwapper();
        proxyAdmin = new ProxyAdmin(proxyAdminOwner);
        bytes memory data = abi.encodeWithSelector(
            StablsscsSwapper.initialize.selector,
            owner,
            operators,
            address(stablsscs),
            address(usdt),
            emergencyOperator,
            emergencyReceiver,
            appConfig
        );
        proxy = new TransparentUpgradeableProxy(
            address(swapperImplementation),
            address(proxyAdmin),
            data
        );
        swapper = StablsscsSwapper(address(proxy));

        // // Deploy implementation and proxy
        // setupProxy(appConfig);

        // Mint initial tokens to users
        usdt.mint(user1, 10000 * 1e6);
        usdt.mint(user2, 10000 * 1e6);
        stablsscs.mint(user1, 10000 * 1e6);
        stablsscs.mint(user2, 10000 * 1e6);

        // Mint tokens to swapper for testing
        usdt.mint(address(swapper), 50000 * 1e6);
        stablsscs.mint(address(swapper), 50000 * 1e6);

        // Set initial fee
        vm.prank(owner);
        swapper.setFee(FEE);
    }

    // function setupProxy(StablsscsSwapper.AppConfig memory appConfig) internal {
    //     // Deploy implementation
    //     swapperImplementation = new StablsscsSwapper();
        
    //     // Deploy proxy admin
    //     proxyAdmin = new ProxyAdmin(proxyAdminOwner);
        
    //     // Deploy proxy
    //     proxy = new TransparentUpgradeableProxy(
    //         address(swapperImplementation),
    //         address(proxyAdmin),
    //         ""
    //     );
        
    //     // Set swapper to use proxy
    //     swapper = StablsscsSwapper(address(proxy));
        
    //     // Initialize the proxy
    //     swapper.initialize(
    //         owner,
    //         new address[](1),
    //         address(stablsscs),
    //         address(usdt),
    //         emergencyOperator,
    //         emergencyReceiver,
    //         appConfig
    //     );
    // }

    // ============ Constructor Tests ============

    function test_Initialize() public {
        assertEq(swapper.owner(), owner);
        assertEq(swapper.emergencyOperator(), emergencyOperator);
        assertEq(swapper.emergencyReceiver(), emergencyReceiver);
        assertEq(swapper.stablsscs(), address(stablsscs));
        assertEq(swapper.usdt(), address(usdt));
        assertEq(swapper.sellStablsscsRatio(), SELL_RATIO);
        assertEq(swapper.buyStablsscsRatio(), BUY_RATIO);
        assertEq(swapper.baseUserLimitUSDT(), BASE_USER_LIMIT);
        assertEq(swapper.baseUserLimitStablsscs(), BASE_USER_LIMIT);
        assertEq(swapper.freezeDurationUSDT(), FREEZE_DURATION);
        assertEq(swapper.freezeDurationStablsscs(), FREEZE_DURATION);
        assertEq(swapper.paused(), false);
        
        // Check if operator was added correctly
        address[] memory operators = swapper.getOperators();
        assertEq(operators.length, 1);
        assertEq(operators[0], operator);
        assertEq(swapper.getOperatorsCount(), 1);
    }

    function test_Initialize_ZeroOwner() public {
        address[] memory operators = new address[](1);
        operators[0] = operator;

        StablsscsSwapper.AppConfig memory appConfig = StablsscsSwapper.AppConfig({
            sellStablsscsRatio: SELL_RATIO,
            buyStablsscsRatio: BUY_RATIO,
            userLimitUpdateIntervalUSDT: 1 days,
            userLimitUpdateIntervalStablsscs: 1 days,
            swapLimitUSDT: 0,
            swapLimitStablsscs: 0,
            baseUserLimitUSDT: BASE_USER_LIMIT,
            baseUserLimitStablsscs: BASE_USER_LIMIT,
            freezeDurationUSDT: FREEZE_DURATION,
            freezeDurationStablsscs: FREEZE_DURATION
        });

        StablsscsSwapper newSwapper = new StablsscsSwapper();
        vm.expectRevert("Owner should be non zero address");
        newSwapper.initialize(
            address(0),
            operators,
            address(stablsscs),
            address(usdt),
            emergencyOperator,
            emergencyReceiver,
            appConfig
        );
    }

    function test_Initialize_ZeroOperator() public {
        address[] memory operators = new address[](1);
        operators[0] = address(0);

        StablsscsSwapper.AppConfig memory appConfig = StablsscsSwapper.AppConfig({
            sellStablsscsRatio: SELL_RATIO,
            buyStablsscsRatio: BUY_RATIO,
            userLimitUpdateIntervalUSDT: 1 days,
            userLimitUpdateIntervalStablsscs: 1 days,
            swapLimitUSDT: 0,
            swapLimitStablsscs: 0,
            baseUserLimitUSDT: BASE_USER_LIMIT,
            baseUserLimitStablsscs: BASE_USER_LIMIT,
            freezeDurationUSDT: FREEZE_DURATION,
            freezeDurationStablsscs: FREEZE_DURATION
        });

        StablsscsSwapper newSwapper = new StablsscsSwapper();
        vm.expectRevert("operator should be non zero address");
        newSwapper.initialize(
            owner,
            operators,
            address(stablsscs),
            address(usdt),
            emergencyOperator,
            emergencyReceiver,
            appConfig
        );
    }

    // ============ Operator Management Tests ============

    function test_GetOperators() public {
        address[] memory operators = swapper.getOperators();
        assertEq(operators.length, 1);
        assertEq(operators[0], operator);
    }

    function test_GetOperatorsCount() public {
        assertEq(swapper.getOperatorsCount(), 1);
    }

    function test_AddOperator() public {
        address newOperator = address(0x999);
        vm.prank(owner);
        swapper.addOperator(newOperator);

        // Check if new operator was added
        address[] memory operators = swapper.getOperators();
        bool found = false;
        for (uint256 i = 0; i < operators.length; i++) {
            if (operators[i] == newOperator) {
                found = true;
                break;
            }
        }
        assertTrue(found);
        assertEq(swapper.getOperatorsCount(), 2);
    }

    function test_AddOperator_NotOwner() public {
        address newOperator = address(0x999);
        vm.prank(user1);
        vm.expectRevert("not owner");
        swapper.addOperator(newOperator);
    }

    function test_AddOperator_AlreadyExists() public {
        vm.prank(owner);
        vm.expectRevert("operator already exists");
        swapper.addOperator(operator);
    }

    function test_AddOperator_Event() public {
        address newOperator = address(0x999);
        
        vm.expectEmit(false, false, false, true);
        emit OperatorAdded(newOperator);
        
        vm.prank(owner);
        swapper.addOperator(newOperator);
    }

    function test_RemoveOperator() public {
        vm.prank(owner);
        swapper.removeOperator(operator);

        // Check if operator was removed
        address[] memory operators = swapper.getOperators();
        bool found = false;
        for (uint256 i = 0; i < operators.length; i++) {
            if (operators[i] == operator) {
                found = true;
                break;
            }
        }
        assertFalse(found);
        assertEq(swapper.getOperatorsCount(), 0);
    }

    function test_RemoveOperator_Event() public {
        vm.expectEmit(false, false, false, true);
        emit OperatorRemoved(operator);
        
        vm.prank(owner);
        swapper.removeOperator(operator);
    }

    function test_RemoveOperator_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert("not owner");
        swapper.removeOperator(operator);
    }

    function test_RemoveOperator_DoesNotExist() public {
        vm.prank(owner);
        vm.expectRevert("operator does not exist");
        swapper.removeOperator(address(0x999));
    }

    function test_MultipleOperators() public {
        address operator1 = address(0x999);
        address operator2 = address(0x888);
        address operator3 = address(0x777);

        // Add multiple operators
        vm.prank(owner);
        swapper.addOperator(operator1);
        
        vm.prank(owner);
        swapper.addOperator(operator2);
        
        vm.prank(owner);
        swapper.addOperator(operator3);

        // Verify all operators were added
        address[] memory operators = swapper.getOperators();
        assertEq(operators.length, 4); // 1 initial + 3 new
        assertEq(swapper.getOperatorsCount(), 4);

        // Remove one operator
        vm.prank(owner);
        swapper.removeOperator(operator2);

        // Verify operator was removed
        operators = swapper.getOperators();
        assertEq(operators.length, 3);
        assertEq(swapper.getOperatorsCount(), 3);

        // Check that remaining operators are still there
        bool foundOperator1 = false;
        bool foundOperator3 = false;
        for (uint256 i = 0; i < operators.length; i++) {
            if (operators[i] == operator1) foundOperator1 = true;
            if (operators[i] == operator3) foundOperator3 = true;
        }
        assertTrue(foundOperator1);
        assertTrue(foundOperator3);
    }

    // ============ Role Management Tests ============

    function test_UpdateOwner() public {
        address newOwner = address(0x999);
        vm.prank(owner);
        swapper.updateOwner(newOwner);
        assertEq(swapper.owner(), newOwner);
    }

    function test_UpdateOwner_NotOwner() public {
        address newOwner = address(0x999);
        vm.prank(user1);
        vm.expectRevert("not owner");
        swapper.updateOwner(newOwner);
    }

    function test_UpdateOwner_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("owner cannot be zero address");
        swapper.updateOwner(address(0));
    }

    // ============ Emergency Operator Tests ============

    function test_UpdateEmergencyOperator() public {
        address newEmergencyOperator = address(0x888);
        vm.prank(owner);
        swapper.updateEmergencyOperator(newEmergencyOperator);
        assertEq(swapper.emergencyOperator(), newEmergencyOperator);
    }

    function test_UpdateEmergencyOperator_NotOwner() public {
        address newEmergencyOperator = address(0x888);
        vm.prank(user1);
        vm.expectRevert("not owner");
        swapper.updateEmergencyOperator(newEmergencyOperator);
    }

    function test_UpdateEmergencyOperator_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("emergency operator cannot be zero address");
        swapper.updateEmergencyOperator(address(0));
    }

    // ============ Emergency Receiver Tests ============

    function test_UpdateEmergencyReceiver() public {
        address newEmergencyReceiver = address(0x999);
        vm.prank(owner);
        swapper.updateEmergencyReceiver(newEmergencyReceiver);
        assertEq(swapper.emergencyReceiver(), newEmergencyReceiver);
    }

    function test_UpdateEmergencyReceiver_NotOwner() public {
        address newEmergencyReceiver = address(0x999);
        vm.prank(user1);
        vm.expectRevert("not owner");
        swapper.updateEmergencyReceiver(newEmergencyReceiver);
    }

    function test_UpdateEmergencyReceiver_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("emergency receiver cannot be zero address");
        swapper.updateEmergencyReceiver(address(0));
    }

    // ============ Emergency Exit Tests ============

    function test_EmergencyExit_Owner() public {
        uint256 initialBalance = usdt.balanceOf(emergencyReceiver);
        uint256 swapperBalance = usdt.balanceOf(address(swapper));

        vm.prank(owner);
        swapper.emergencyExit();

        assertEq(usdt.balanceOf(emergencyReceiver), initialBalance + swapperBalance);
        assertEq(usdt.balanceOf(address(swapper)), 0);
    }

    function test_EmergencyExit_EmergencyOperator() public {
        uint256 initialBalance = usdt.balanceOf(emergencyReceiver);
        uint256 swapperBalance = usdt.balanceOf(address(swapper));

        vm.prank(emergencyOperator);
        swapper.emergencyExit();

        assertEq(usdt.balanceOf(emergencyReceiver), initialBalance + swapperBalance);
        assertEq(usdt.balanceOf(address(swapper)), 0);
    }

    function test_EmergencyExit_Operator() public {
        uint256 initialBalance = usdt.balanceOf(emergencyReceiver);
        uint256 swapperBalance = usdt.balanceOf(address(swapper));

        vm.prank(operator);
        swapper.emergencyExit();

        assertEq(usdt.balanceOf(emergencyReceiver), initialBalance + swapperBalance);
        assertEq(usdt.balanceOf(address(swapper)), 0);
    }

    function test_EmergencyExit_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("not owner or operator or emergency operator");
        swapper.emergencyExit();
    }

    function test_EmergencyExit_EmptyBalance() public {
        // First drain the swapper
        vm.prank(owner);
        swapper.emergencyExit();

        // Try emergency exit again - should work but transfer 0
        uint256 initialBalance = usdt.balanceOf(emergencyReceiver);
        vm.prank(owner);
        swapper.emergencyExit();

        assertEq(usdt.balanceOf(emergencyReceiver), initialBalance);
        assertEq(usdt.balanceOf(address(swapper)), 0);
    }

    function test_EmergencyExit_AfterPause() public {
        // Pause the contract
        vm.prank(owner);
        swapper.pause();

        // Emergency exit should still work when paused
        uint256 initialBalance = usdt.balanceOf(emergencyReceiver);
        uint256 swapperBalance = usdt.balanceOf(address(swapper));

        vm.prank(owner);
        swapper.emergencyExit();

        assertEq(usdt.balanceOf(emergencyReceiver), initialBalance + swapperBalance);
        assertEq(usdt.balanceOf(address(swapper)), 0);
    }

    // ============ Pause/Unpause Tests ============

    function test_Pause_Owner() public {
        vm.prank(owner);
        swapper.pause();
        assertEq(swapper.paused(), true);
    }

    function test_Pause_Operator() public {
        vm.prank(operator);
        swapper.pause();
        assertEq(swapper.paused(), true);
    }

    function test_Pause_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("not owner or operator");
        swapper.pause();
    }

    function test_Pause_AlreadyPaused() public {
        vm.prank(owner);
        swapper.pause();
        vm.prank(owner);
        vm.expectRevert("protocol paused");
        swapper.pause();
    }

    function test_Unpause_Owner() public {
        vm.prank(owner);
        swapper.pause();
        vm.prank(owner);
        swapper.unpause();
        assertEq(swapper.paused(), false);
    }

    function test_Unpause_Operator() public {
        vm.prank(owner);
        swapper.pause();
        vm.prank(operator);
        swapper.unpause();
        assertEq(swapper.paused(), false);
    }

    function test_Unpause_NotAuthorized() public {
        vm.prank(owner);
        swapper.pause();
        vm.prank(user1);
        vm.expectRevert("not owner or operator");
        swapper.unpause();
    }

    // ============ Supply/Withdraw Tests ============

    function test_SupplyUSDT() public {
        uint256 amount = 1000 * 1e6;
        uint256 initialBalance = usdt.balanceOf(address(swapper));

        vm.startPrank(user1);
        usdt.approve(address(swapper), amount);
        swapper.supplyUSDT(amount);
        vm.stopPrank();

        assertEq(usdt.balanceOf(address(swapper)), initialBalance + amount);
    }

    function test_SupplyUSDT_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("supply amount cannot be zero");
        swapper.supplyUSDT(0);
    }

    function test_SupplyStablsscs() public {
        uint256 amount = 1000 * 1e6;
        uint256 initialBalance = stablsscs.balanceOf(address(swapper));

        vm.startPrank(user1);
        stablsscs.approve(address(swapper), amount);
        swapper.supplyStablsscs(amount);
        vm.stopPrank();

        assertEq(stablsscs.balanceOf(address(swapper)), initialBalance + amount);
    }

    function test_SupplyStablsscs_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("supply amount cannot be zero");
        swapper.supplyStablsscs(0);
    }

    function test_WithdrawUSDT_Owner() public {
        uint256 amount = 1000 * 1e6;
        uint256 initialBalance = usdt.balanceOf(owner);

        vm.prank(owner);
        swapper.withdrawUSDT(amount);

        assertEq(usdt.balanceOf(owner), initialBalance + amount);
    }

    function test_WithdrawUSDT_Operator() public {
        uint256 amount = 1000 * 1e6;
        uint256 initialBalance = usdt.balanceOf(operator);

        vm.prank(operator);
        swapper.withdrawUSDT(amount);

        assertEq(usdt.balanceOf(operator), initialBalance + amount);
    }

    function test_WithdrawUSDT_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("not owner or operator");
        swapper.withdrawUSDT(1000 * 1e6);
    }

    function test_WithdrawUSDT_ZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert("withdraw amount cannot be zero");
        swapper.withdrawUSDT(0);
    }

    function test_WithdrawStablsscs_Owner() public {
        uint256 amount = 1000 * 1e6;
        uint256 initialBalance = stablsscs.balanceOf(owner);

        vm.prank(owner);
        swapper.withdrawStablsscs(amount);

        assertEq(stablsscs.balanceOf(owner), initialBalance + amount);
    }

    function test_WithdrawStablsscs_Operator() public {
        uint256 amount = 1000 * 1e6;
        uint256 initialBalance = stablsscs.balanceOf(operator);

        vm.prank(operator);
        swapper.withdrawStablsscs(amount);

        assertEq(stablsscs.balanceOf(operator), initialBalance + amount);
    }

    function test_WithdrawStablsscs_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("not owner or operator");
        swapper.withdrawStablsscs(1000 * 1e6);
    }

    function test_WithdrawStablsscs_ZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert("withdraw amount cannot be zero");
        swapper.withdrawStablsscs(0);
    }

    // ============ Parameter Setting Tests ============

    function test_SetSellStablsscsRatio_Owner() public {
        uint256 newRatio = 1200000; // 1.2:1
        vm.prank(owner);
        swapper.setSellStablsscsRatio(newRatio);
        assertEq(swapper.sellStablsscsRatio(), newRatio);
    }

    function test_SetSellStablsscsRatio_Operator() public {
        uint256 newRatio = 1200000; // 1.2:1
        vm.prank(operator);
        swapper.setSellStablsscsRatio(newRatio);
        assertEq(swapper.sellStablsscsRatio(), newRatio);
    }

    function test_SetSellStablsscsRatio_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("not owner or operator");
        swapper.setSellStablsscsRatio(1200000);
    }

    function test_SetSellStablsscsRatio_ZeroRatio() public {
        vm.prank(owner);
        vm.expectRevert("sell ratio cannot be 0");
        swapper.setSellStablsscsRatio(0);
    }

    function test_SetBuyStablsscsRatio_Owner() public {
        uint256 newRatio = 1200000; // 1.2:1
        vm.prank(owner);
        swapper.setBuyStablsscsRatio(newRatio);
        assertEq(swapper.buyStablsscsRatio(), newRatio);
    }

    function test_SetBuyStablsscsRatio_Operator() public {
        uint256 newRatio = 1200000; // 1.2:1
        vm.prank(operator);
        swapper.setBuyStablsscsRatio(newRatio);
        assertEq(swapper.buyStablsscsRatio(), newRatio);
    }

    function test_SetBuyStablsscsRatio_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("not owner or operator");
        swapper.setBuyStablsscsRatio(1200000);
    }

    function test_SetBuyStablsscsRatio_ZeroRatio() public {
        vm.prank(owner);
        vm.expectRevert("buy ratio cannot be 0");
        swapper.setBuyStablsscsRatio(0);
    }

    function test_SetSwapLimitUSDT_Owner() public {
        uint256 newLimit = 5000 * 1e6;
        vm.prank(owner);
        swapper.setSwapLimitUSDT(newLimit);
        assertEq(swapper.swapLimitUSDT(), newLimit);
    }

    function test_SetSwapLimitUSDT_Operator() public {
        uint256 newLimit = 5000 * 1e6;
        vm.prank(operator);
        swapper.setSwapLimitUSDT(newLimit);
        assertEq(swapper.swapLimitUSDT(), newLimit);
    }

    function test_SetSwapLimitUSDT_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("not owner or operator");
        swapper.setSwapLimitUSDT(5000 * 1e6);
    }

    function test_SetBaseUserLimitUSDT_Owner() public {
        uint256 newLimit = 2000 * 1e6;
        vm.prank(owner);
        swapper.setBaseUserLimitUSDT(newLimit);
        assertEq(swapper.baseUserLimitUSDT(), newLimit);
    }

    function test_SetBaseUserLimitUSDT_Operator() public {
        uint256 newLimit = 2000 * 1e6;
        vm.prank(operator);
        swapper.setBaseUserLimitUSDT(newLimit);
        assertEq(swapper.baseUserLimitUSDT(), newLimit);
    }

    function test_SetBaseUserLimitUSDT_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("not owner or operator");
        swapper.setBaseUserLimitUSDT(2000 * 1e6);
    }

    function test_SetFreezeDuration_Owner() public {
        uint256 newDuration = 7200; // 2 hours
        vm.prank(owner);
        swapper.setFreezeDurationUSDT(newDuration);
        assertEq(swapper.freezeDurationUSDT(), newDuration);
    }

    function test_SetFreezeDuration_Operator() public {
        uint256 newDuration = 7200; // 2 hours
        vm.prank(operator);
        swapper.setFreezeDurationUSDT(newDuration);
        assertEq(swapper.freezeDurationUSDT(), newDuration);
    }

    function test_SetFreezeDuration_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("not owner or operator");
        swapper.setFreezeDurationUSDT(7200);
    }

    function test_SetFee_Owner() public {
        uint256 newFee = 30000; // 3%
        vm.prank(owner);
        swapper.setFee(newFee);
        assertEq(swapper.fee(), newFee);
    }

    function test_SetFee_Operator() public {
        uint256 newFee = 30000; // 3%
        vm.prank(operator);
        swapper.setFee(newFee);
        assertEq(swapper.fee(), newFee);
    }

    function test_SetFee_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("not owner or operator");
        swapper.setFee(30000);
    }

    function test_SetFee_InvalidFee() public {
        vm.prank(owner);
        vm.expectRevert();
        swapper.setFee(1000001); // Greater than FEE_DENOMINATOR
    }

    // ============ User Limit Update Interval Tests ============

    function test_UpdateUserLimitUpdateIntervalUSDT_Owner() public {
        uint256 newInterval = 2 days;
        vm.prank(owner);
        swapper.updateUserLimitUpdateIntervalUSDT(newInterval);
        assertEq(swapper.userLimitUpdateIntervalUSDT(), newInterval);
    }

    function test_UpdateUserLimitUpdateIntervalUSDT_Operator() public {
        uint256 newInterval = 2 days;
        vm.prank(operator);
        swapper.updateUserLimitUpdateIntervalUSDT(newInterval);
        assertEq(swapper.userLimitUpdateIntervalUSDT(), newInterval);
    }

    function test_UpdateUserLimitUpdateIntervalUSDT_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert("not owner or operator");
        swapper.updateUserLimitUpdateIntervalUSDT(2 days);
    }

    function test_UpdateUserLimitUpdateIntervalUSDT_ZeroInterval() public {
        vm.prank(owner);
        swapper.updateUserLimitUpdateIntervalUSDT(0);
        assertEq(swapper.userLimitUpdateIntervalUSDT(), 0);
    }

    function test_UpdateUserLimitUpdateIntervalUSDT_LargeInterval() public {
        uint256 largeInterval = 365 days;
        vm.prank(owner);
        swapper.updateUserLimitUpdateIntervalUSDT(largeInterval);
        assertEq(swapper.userLimitUpdateIntervalUSDT(), largeInterval);
    }

    function test_UpdateUserLimitUpdateIntervalUSDT_Event() public {
        uint256 newInterval = 2 days;
        
        vm.expectEmit(false, false, false, true);
        emit UserLimitUpdateIntervalUSDTUpdated(newInterval);
        
        vm.prank(owner);
        swapper.updateUserLimitUpdateIntervalUSDT(newInterval);
    }

    // ============ Exchange Tests ============

    function test_ExchangeStablsscsToUSDT() public {
        uint256 stablsscsAmount = 1000 * 1e6;
        uint256 expectedUsdtAmount = stablsscsAmount * (1000000 - FEE) / 1000000 * SELL_RATIO / 1000000;

        uint256 initialUserStablsscs = stablsscs.balanceOf(user1);
        uint256 initialUserUsdt = usdt.balanceOf(user1);
        uint256 initialSwapperStablsscs = stablsscs.balanceOf(address(swapper));
        uint256 initialSwapperUsdt = usdt.balanceOf(address(swapper));

        vm.startPrank(user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();

        assertEq(stablsscs.balanceOf(user1), initialUserStablsscs - stablsscsAmount);
        assertEq(usdt.balanceOf(user1), initialUserUsdt + expectedUsdtAmount);
        assertEq(stablsscs.balanceOf(address(swapper)), initialSwapperStablsscs + stablsscsAmount);
        assertEq(usdt.balanceOf(address(swapper)), initialSwapperUsdt - expectedUsdtAmount);
    }

    function test_ExchangeStablsscsToUSDT_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("exchange amount cannot be zero");
        swapper.exchangeStablsscsToUSDT(0);
    }

    function test_ExchangeStablsscsToUSDT_WhenPaused() public {
        vm.prank(owner);
        swapper.pause();

        vm.prank(user1);
        vm.expectRevert("protocol paused");
        swapper.exchangeStablsscsToUSDT(1000 * 1e6);
    }

    function test_ExchangeStablsscsToUSDT_SwapLimitExceeded() public {
        vm.prank(owner);
        swapper.setSwapLimitUSDT(100 * 1e6); // Set low limit

        uint256 stablsscsAmount = 200 * 1e6; // Amount that would exceed the limit
        vm.startPrank(user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        vm.expectRevert("swap limit for one tx to USDT exceeded");
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();
    }

    function test_ExchangeStablsscsToUSDT_InsufficientTokens() public {
        // Drain swapper's USDT balance
        vm.startPrank(owner);
        swapper.withdrawUSDT(usdt.balanceOf(address(swapper)));

        uint256 stablsscsAmount = 1000 * 1e6;
        vm.startPrank(user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        vm.expectRevert("not enough tokens for swap");
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();
    }

    function test_ExchangeStablsscsToUSDT_UserLimitExceeded() public {
        uint256 stablsscsAmount = 2000 * 1e6; // Amount that would exceed user limit
        vm.startPrank(user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        vm.expectRevert("user USDT limit exceeded");
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();
    }

    function test_ExchangeStablsscsToUSDT_FreezeDuration() public {
        uint256 stablsscsAmount = 100 * 1e6;

        // First swap
        vm.startPrank(user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();

        // Try to swap again immediately
        vm.startPrank(user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        vm.expectRevert("swap to USDT is frozen");
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();

        // Wait for freeze duration to pass
        vm.warp(block.timestamp + FREEZE_DURATION + 1);

        // Should work now
        vm.startPrank(user1);
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();
    }

    function test_ExchangeStablsscsToUSDT_TxOriginFreeze() public {
        uint256 stablsscsAmount = 100 * 1e6;

        // First swap - should set freeze for both msg.sender and tx.origin
        vm.startPrank(user1, user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();

        // Try to swap again with same tx.origin but different msg.sender
        vm.startPrank(user2, user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        vm.expectRevert("swap to USDT is frozen");
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();

        // Wait for freeze duration to pass
        vm.warp(block.timestamp + FREEZE_DURATION + 1);

        // Should work now
        vm.startPrank(user2, user2);
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();
    }

    function test_ExchangeStablsscsToUSDT_UserLimitReset() public {
        uint256 stablsscsAmount = 500 * 1e6;

        // First swap
        vm.startPrank(user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();

        // Wait for limit update interval
        vm.warp(block.timestamp + 1 days + 1);

        // Should be able to swap again (limit reset)
        vm.startPrank(user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();
    }

    function test_UserLimitWithCustomInterval() public {
        uint256 customInterval = 12 hours;
        vm.prank(owner);
        swapper.updateUserLimitUpdateIntervalUSDT(customInterval);

        uint256 stablsscsAmount = 500 * 1e6;

        // First swap
        vm.startPrank(user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();

        // Wait for custom interval
        vm.warp(block.timestamp + customInterval + 1);

        // Should be able to swap again (limit reset)
        vm.startPrank(user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();
    }

    function test_ExchangeUSDTToStablsscs() public {
        uint256 usdtAmount = 1000 * 1e6;
        uint256 expectedStablsscsAmount = usdtAmount * (1000000 - FEE) / 1000000 * BUY_RATIO / 1000000;

        uint256 initialUserUsdt = usdt.balanceOf(user1);
        uint256 initialUserStablsscs = stablsscs.balanceOf(user1);
        uint256 initialSwapperUsdt = usdt.balanceOf(address(swapper));
        uint256 initialSwapperStablsscs = stablsscs.balanceOf(address(swapper));

        vm.startPrank(user1);
        usdt.approve(address(swapper), usdtAmount);
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();

        assertEq(usdt.balanceOf(user1), initialUserUsdt - usdtAmount);
        assertEq(stablsscs.balanceOf(user1), initialUserStablsscs + expectedStablsscsAmount);
        assertEq(usdt.balanceOf(address(swapper)), initialSwapperUsdt + usdtAmount);
        assertEq(stablsscs.balanceOf(address(swapper)), initialSwapperStablsscs - expectedStablsscsAmount);
    }

    function test_ExchangeUSDTToStablsscs_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("exchange amount cannot be zero");
        swapper.exchangeUSDTToStablsscs(0);
    }

    function test_ExchangeUSDTToStablsscs_WhenPaused() public {
        vm.prank(owner);
        swapper.pause();

        vm.prank(user1);
        vm.expectRevert("protocol paused");
        swapper.exchangeUSDTToStablsscs(1000 * 1e6);
    }

    function test_ExchangeUSDTToStablsscs_InsufficientTokens() public {
        // Drain swapper's Stablsscs balance
        vm.startPrank(owner);
        swapper.withdrawStablsscs(stablsscs.balanceOf(address(swapper)));

        uint256 usdtAmount = 1000 * 1e6;
        vm.startPrank(user1);
        usdt.approve(address(swapper), usdtAmount);
        vm.expectRevert("not enough tokens for swap");
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();
    }

    function test_ExchangeUSDTToStablsscs_SwapLimitExceeded() public {
        vm.prank(owner);
        swapper.setSwapLimitStablsscs(100 * 1e6); // Set low Stablsscs limit per tx

        uint256 usdtAmount = 200 * 1e6; // After 5% fee -> 190 Stablsscs > 100 limit
        vm.startPrank(user1);
        usdt.approve(address(swapper), usdtAmount);
        vm.expectRevert("swap limit for one tx to Stablsscs exceeded");
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();
    }

    function test_ExchangeUSDTToStablsscs_UserLimitExceeded() public {
        // baseUserLimitStablsscs is 1000e6; exceed it after fee
        uint256 usdtAmount = 2000 * 1e6; // -> 1900 Stablsscs > 1000 limit
        vm.startPrank(user1);
        usdt.approve(address(swapper), usdtAmount);
        vm.expectRevert("user Stablsscs limit exceeded");
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();
    }

    function test_ExchangeUSDTToStablsscs_FreezeDuration() public {
        uint256 usdtAmount = 100 * 1e6;

        // First swap
        vm.startPrank(user1);
        usdt.approve(address(swapper), usdtAmount);
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();

        // Try to swap again immediately
        vm.startPrank(user1);
        usdt.approve(address(swapper), usdtAmount);
        vm.expectRevert("swap to Stablsscs is frozen");
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();

        // Wait for freeze duration to pass
        vm.warp(block.timestamp + FREEZE_DURATION + 1);

        // Should work now
        vm.startPrank(user1);
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();
    }

    function test_ExchangeUSDTToStablsscs_TxOriginFreeze() public {
        uint256 usdtAmount = 100 * 1e6;

        // First swap - should set freeze for both msg.sender and tx.origin
        vm.startPrank(user1, user1);
        usdt.approve(address(swapper), usdtAmount);
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();

        // Try to swap again with same tx.origin but different msg.sender
        vm.startPrank(user2, user1);
        usdt.approve(address(swapper), usdtAmount);
        vm.expectRevert("swap to Stablsscs is frozen");
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();

        // Wait for freeze duration to pass
        vm.warp(block.timestamp + FREEZE_DURATION + 1);

        // Should work now
        vm.startPrank(user2, user2);
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();
    }

    function test_ExchangeUSDTToStablsscs_UserLimitReset() public {
        uint256 usdtAmount = 500 * 1e6; // -> 475 Stablsscs

        // First swap
        vm.startPrank(user1);
        usdt.approve(address(swapper), usdtAmount);
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();

        // Wait for limit update interval (Stablsscs side)
        vm.warp(block.timestamp + 1 days + 1);

        // Should be able to swap again (limit reset)
        vm.startPrank(user1);
        usdt.approve(address(swapper), usdtAmount);
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();
    }

    function test_UserLimitWithCustomInterval_Stablsscs() public {
        uint256 customInterval = 12 hours;
        vm.prank(owner);
        swapper.updateUserLimitUpdateIntervalStablsscs(customInterval);

        uint256 usdtAmount = 500 * 1e6;

        // First swap
        vm.startPrank(user1);
        usdt.approve(address(swapper), usdtAmount);
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();

        // Wait for custom interval
        vm.warp(block.timestamp + customInterval + 1);

        // Should be able to swap again (limit reset)
        vm.startPrank(user1);
        usdt.approve(address(swapper), usdtAmount);
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();
    }

    // ============ Fuzz Tests ============

    function testFuzz_ExchangeStablsscsToUSDT(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 * 1e6); // Smaller amount to avoid limits

        vm.startPrank(user1);
        stablsscs.approve(address(swapper), amount);
        swapper.exchangeStablsscsToUSDT(amount);
        vm.stopPrank();

        // Verify user received USDT
        assertGt(usdt.balanceOf(user1), 0);
    }

    function testFuzz_ExchangeUSDTToStablsscs(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 * 1e6);

        vm.startPrank(user1);
        usdt.approve(address(swapper), amount);
        swapper.exchangeUSDTToStablsscs(amount);
        vm.stopPrank();

        // Verify user received Stablsscs
        assertGt(stablsscs.balanceOf(user1), 0);
    }

    function testFuzz_SetFee(uint256 fee) public {
        vm.assume(fee < 1000000); // Less than FEE_DENOMINATOR

        vm.prank(owner);
        swapper.setFee(fee);
        assertEq(swapper.fee(), fee);
    }

    // ============ Integration Tests ============

    function test_CompleteSwapCycle() public {
        uint256 stablsscsAmount = 1000 * 1e6;

        // User1 swaps Stablsscs to USDT
        vm.startPrank(user1);
        stablsscs.approve(address(swapper), stablsscsAmount);
        swapper.exchangeStablsscsToUSDT(stablsscsAmount);
        vm.stopPrank();

        // Wait for freeze duration
        vm.warp(block.timestamp + FREEZE_DURATION + 1);

        // User1 swaps USDT back to Stablsscs
        uint256 usdtAmount = 800 * 1e6; // Less than what they received
        vm.startPrank(user1);
        usdt.approve(address(swapper), usdtAmount);
        swapper.exchangeUSDTToStablsscs(usdtAmount);
        vm.stopPrank();

        // Verify user has both tokens
        assertGt(stablsscs.balanceOf(user1), 0);
        assertGt(usdt.balanceOf(user1), 0);
    }

    function test_MultipleUsersSwapping() public {
        uint256 amount = 500 * 1e6;

        // User1 swaps
        vm.startPrank(user1);
        stablsscs.approve(address(swapper), amount);
        swapper.exchangeStablsscsToUSDT(amount);
        vm.stopPrank();

        // User2 swaps
        vm.startPrank(user2);
        usdt.approve(address(swapper), amount);
        swapper.exchangeUSDTToStablsscs(amount);
        vm.stopPrank();

        // Both users should have received tokens
        assertGt(usdt.balanceOf(user1), 0);
        assertGt(stablsscs.balanceOf(user2), 0);
    }

    // ============ Proxy Tests ============

    function test_ProxyDeployment() public {
        // Verify proxy is deployed and points to implementation
        assertEq(address(swapper), address(proxy));
        
        // Verify proxy admin ownership
        assertEq(proxyAdmin.owner(), proxyAdminOwner);
    }

    function test_ProxyAdminOwnership() public {
        assertEq(proxyAdmin.owner(), proxyAdminOwner);
    }

    function test_ProxyUpgrade_NotAdmin() public {
        StablsscsSwapper newImplementation = new StablsscsSwapper();
        
        vm.prank(user1);
        vm.expectRevert();
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(newImplementation), "");
    }
}
