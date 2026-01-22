// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {TokenLaunchHook} from "../src/TokenLaunchHook.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

contract TestTokenLaunchHook is Test, Deployers, ERC1155TokenReceiver {
    MockERC20 token;
    TokenLaunchHook public antiBotHook;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    address user1 = address(0x1);
    address user2 = address(0x2);
    address bot1 = address(0xB0B1);
    address bot2 = address(0xB0B2);

    uint160 constant SQRT_PRICE_1_1_s = 79228162514264337593543950336;

    uint256 phase1Duration = 100;
    uint256 phase2Duration = 100;
    uint256 phase1LimitBps = 100;
    uint256 phase2LimitBps = 500;
    uint256 phase1Cooldown = 5;
    uint256 phase2Cooldown = 2;
    uint256 phase1PenaltyBps = 1000;
    uint256 phase2PenaltyBps = 500;

    function setUp() public {
        deployFreshManagerAndRouters();

        token = new MockERC20("TOKEN", "TKN", 18);
        tokenCurrency = Currency.wrap(address(token));

        token.mint(address(this), 1000 ether);
        token.mint(user1, 1000 ether);
        token.mint(user2, 1000 ether);
        token.mint(bot1, 1000 ether);
        token.mint(bot2, 1000 ether);

        bytes memory creationCode = type(TokenLaunchHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            manager,
            phase1Duration,
            phase2Duration,
            phase1LimitBps,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );

        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);

        (address hookAddress, bytes32 salt) = HookMiner.find(address(this), flags, creationCode, constructorArgs);

        antiBotHook = new TokenLaunchHook{salt: salt}(
            manager,
            phase1Duration,
            phase2Duration,
            phase1LimitBps,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );
        require(address(antiBotHook) == hookAddress, "Hook address mismatch");

        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        vm.prank(user1);
        token.approve(address(swapRouter), type(uint256).max);
        vm.prank(user2);
        token.approve(address(swapRouter), type(uint256).max);
        vm.prank(bot1);
        token.approve(address(swapRouter), type(uint256).max);
        vm.prank(bot2);
        token.approve(address(swapRouter), type(uint256).max);

        (key,) = initPool(ethCurrency, tokenCurrency, antiBotHook, LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1_s);

        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint256 ethToAdd = 10 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, ethToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    /* ══════════════════════════════════════════════════════════════════
                            INITIALIZATION TESTS
       ══════════════════════════════════════════════════════════════════ */

    function test_DeploymentSuccess() public view {
        assertEq(antiBotHook.currentPhase(), 1, "Should start in phase 1");
        assertEq(antiBotHook.launchStartBlock(), block.number, "Launch block should be set");
        assertEq(antiBotHook.initialLiquidity(), 0, "Initial liquidity is 0 before first swap");
    }

    function test_ImmutableParameters() public view {
        assertEq(antiBotHook.phase1Duration(), phase1Duration, "Phase 1 duration mismatch");
        assertEq(antiBotHook.phase2Duration(), phase2Duration, "Phase 2 duration mismatch");
        assertEq(antiBotHook.phase1LimitBps(), phase1LimitBps, "Phase 1 limit bps mismatch");
        assertEq(antiBotHook.phase2LimitBps(), phase2LimitBps, "Phase 2 limit bps mismatch");
        assertEq(antiBotHook.phase1Cooldown(), phase1Cooldown, "Phase 1 cooldown mismatch");
        assertEq(antiBotHook.phase2Cooldown(), phase2Cooldown, "Phase 2 cooldown mismatch");
        assertEq(antiBotHook.phase1PenaltyBps(), phase1PenaltyBps, "Phase 1 penalty bps mismatch");
        assertEq(antiBotHook.phase2PenaltyBps(), phase2PenaltyBps, "Phase 2 penalty bps mismatch");
    }

    function test_InvalidConstructorParams() public {
        bytes memory creationCode = type(TokenLaunchHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            manager,
            0,
            phase2Duration,
            phase1LimitBps,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );

        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);
        (, bytes32 salt) = HookMiner.find(address(this), flags, creationCode, constructorArgs);

        vm.expectRevert(TokenLaunchHook.InvalidConstructorParams.selector);
        new TokenLaunchHook{salt: salt}(
            manager,
            0,
            phase2Duration,
            phase1LimitBps,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );
    }

    function test_InvalidBpsParams() public {
        bytes memory creationCode = type(TokenLaunchHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            manager,
            phase1Duration,
            phase2Duration,
            10001,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );

        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);
        (, bytes32 salt) = HookMiner.find(address(this), flags, creationCode, constructorArgs);

        vm.expectRevert(TokenLaunchHook.InvalidConstructorParams.selector);
        new TokenLaunchHook{salt: salt}(
            manager,
            phase1Duration,
            phase2Duration,
            10001,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );
    }

    function test_MustUseDynamicFee() public {
        bytes memory creationCode = type(TokenLaunchHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            manager,
            phase1Duration,
            phase2Duration,
            phase1LimitBps,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );

        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);
        (, bytes32 salt) = HookMiner.find(address(this), flags, creationCode, constructorArgs);

        TokenLaunchHook newHook = new TokenLaunchHook{salt: salt}(
            manager,
            phase1Duration,
            phase2Duration,
            phase1LimitBps,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );

        vm.expectRevert();
        initPool(ethCurrency, tokenCurrency, newHook, 3000, SQRT_PRICE_1_1_s);
    }

    /* ══════════════════════════════════════════════════════════════════
                            PHASE TRANSITION TESTS
       ══════════════════════════════════════════════════════════════════ */

    function test_PhaseTransition_Phase1ToPhase2() public {
        assertEq(antiBotHook.getCurrentPhase(), 1, "Should start in phase 1");

        vm.roll(block.number + phase1Duration + 1);

        vm.deal(user1, 1 ether);
        vm.startPrank(user1);
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        assertEq(antiBotHook.getCurrentPhase(), 2, "Should be in phase 2");
        assertEq(antiBotHook.currentPhase(), 2, "Current phase state should be 2");
    }

    function test_PhaseTransition_Phase2ToPhase3() public {
        vm.roll(block.number + phase1Duration + phase2Duration + 1);

        vm.deal(user1, 1 ether);
        vm.startPrank(user1);
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        assertEq(antiBotHook.getCurrentPhase(), 3, "Should be in phase 3");
        assertEq(antiBotHook.currentPhase(), 3, "Current phase state should be 3");
    }

    function test_PhaseTransition_ResetsTracking() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);

        // Check that swapRouter has swapped (since sender is the router)
        assertGt(antiBotHook.addressSwappedAmount(address(swapRouter)), 0, "SwapRouter should have swapped amount");

        vm.stopPrank();

        uint256 phase1End = antiBotHook.launchStartBlock() + phase1Duration;
        vm.roll(phase1End + 1);

        vm.startPrank(user1);
        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        assertEq(antiBotHook.currentPhase(), 2, "Should be in phase 2");
    }

    /* ══════════════════════════════════════════════════════════════════
                            SWAP LIMIT TESTS - PHASE 1
       ══════════════════════════════════════════════════════════════════ */

    function test_Phase1_SwapWithinLimit() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);

        uint256 swapAmount = 0.001 ether;

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: swapAmount}(key, params, testSettings, ZERO_BYTES);

        assertGt(antiBotHook.addressSwappedAmount(address(swapRouter)), 0, "Swap amount should be recorded for router");

        vm.stopPrank();
    }

    function test_Phase1_SwapExceedsLimit() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);

        assertGt(antiBotHook.addressSwappedAmount(address(swapRouter)), 0, "Should have swapped");

        vm.stopPrank();
    }

    function test_Phase1_MultipleUsersRespectiveLimits() public {
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);

        uint256 swapAmount = 0.001 ether;

        vm.startPrank(user1);
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: swapAmount}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        vm.startPrank(user2);
        swapRouter.swap{value: swapAmount}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        assertGt(
            antiBotHook.addressSwappedAmount(address(swapRouter)), swapAmount, "Router should have accumulated swaps"
        );
    }

    /* ══════════════════════════════════════════════════════════════════
                            COOLDOWN TESTS - PHASE 1
       ══════════════════════════════════════════════════════════════════ */

    function test_Phase1_CooldownViolation() public {
        vm.deal(bot1, 10 ether);
        vm.startPrank(bot1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);

        uint256 cooldownEnd = antiBotHook.getUserCooldownEnd(address(swapRouter));
        assertGt(cooldownEnd, block.number, "Cooldown should not have ended");

        vm.stopPrank();
    }

    function test_Phase1_CooldownRespected() public {
        vm.deal(bot1, 10 ether);
        vm.startPrank(bot1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);

        vm.roll(block.number + phase1Cooldown + 1);

        uint256 cooldownEnd = antiBotHook.getUserCooldownEnd(address(swapRouter));
        assertEq(cooldownEnd, 0, "Cooldown should have ended");

        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);

        vm.stopPrank();
    }

    /* ══════════════════════════════════════════════════════════════════
                            SWAP LIMIT TESTS - PHASE 2
       ══════════════════════════════════════════════════════════════════ */

    function test_Phase2_HigherSwapLimit() public {
        vm.roll(block.number + phase1Duration + 1);

        vm.deal(user1, 10 ether);
        vm.startPrank(user1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);

        assertEq(antiBotHook.currentPhase(), 2, "Should be in phase 2");

        vm.stopPrank();
    }

    function test_Phase2_ShorterCooldown() public {
        vm.roll(block.number + phase1Duration + 1);

        vm.deal(bot1, 10 ether);
        vm.startPrank(bot1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);

        vm.roll(block.number + phase2Cooldown + 1);

        uint256 cooldownEnd = antiBotHook.getUserCooldownEnd(address(swapRouter));
        assertEq(cooldownEnd, 0, "Cooldown should have ended");

        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);

        vm.stopPrank();
    }

    /* ══════════════════════════════════════════════════════════════════
                            PHASE 3 - NO RESTRICTIONS
       ══════════════════════════════════════════════════════════════════ */

    function test_Phase3_NoSwapLimit() public {
        vm.roll(block.number + phase1Duration + phase2Duration + 1);

        vm.deal(user1, 10 ether);
        vm.startPrank(user1);

        uint256 remainingLimit = antiBotHook.getUserRemainingLimit(address(swapRouter));
        assertEq(remainingLimit, type(uint256).max, "Phase 3 should have no limit");

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        for (uint256 i = 0; i < 5; i++) {
            swapRouter.swap{value: 1 ether}(key, params, testSettings, ZERO_BYTES);
        }

        vm.stopPrank();
    }

    function test_Phase3_NoCooldown() public {
        vm.roll(block.number + phase1Duration + phase2Duration + 1);

        vm.deal(bot1, 10 ether);
        vm.startPrank(bot1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        for (uint256 i = 0; i < 10; i++) {
            swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        }

        uint256 cooldownEnd = antiBotHook.getUserCooldownEnd(address(swapRouter));
        assertEq(cooldownEnd, 0, "Phase 3 should have no cooldown");

        vm.stopPrank();
    }

    /* ══════════════════════════════════════════════════════════════════
                            VIEW FUNCTION TESTS
       ══════════════════════════════════════════════════════════════════ */

    function test_GetCurrentPhase_Phase1() public view {
        assertEq(antiBotHook.getCurrentPhase(), 1, "Should be in phase 1");
    }

    function test_GetCurrentPhase_Phase2() public {
        vm.roll(block.number + phase1Duration + 1);
        assertEq(antiBotHook.getCurrentPhase(), 2, "Should be in phase 2");
    }

    function test_GetCurrentPhase_Phase3() public {
        vm.roll(block.number + phase1Duration + phase2Duration + 1);
        assertEq(antiBotHook.getCurrentPhase(), 3, "Should be in phase 3");
    }

    function test_GetUserRemainingLimit_NoSwaps() public view {
        uint256 remainingLimit = antiBotHook.getUserRemainingLimit(user1);
        assertEq(remainingLimit, 0, "Should have 0 limit when initialLiquidity is 0");
    }

    function test_GetUserRemainingLimit_AfterSwaps() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);

        uint256 swapAmount = 0.001 ether;

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: swapAmount}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        assertGt(antiBotHook.addressSwappedAmount(address(swapRouter)), 0, "Swap amount should be recorded");
    }

    function test_GetUserCooldownEnd_NoSwaps() public view {
        uint256 cooldownEnd = antiBotHook.getUserCooldownEnd(user1);
        assertEq(cooldownEnd, 0, "Should have no cooldown");
    }

    function test_GetUserCooldownEnd_AfterSwap() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        uint256 cooldownEnd = antiBotHook.getUserCooldownEnd(address(swapRouter));
        assertGt(cooldownEnd, block.number, "Should have active cooldown");
    }

    function test_GetPhaseConfig_Phase2() public view {
        (uint256 duration, uint256 limitBps, uint256 cooldown, uint256 penaltyBps) = antiBotHook.getPhaseConfig(2);

        assertEq(duration, phase2Duration, "Phase 2 duration mismatch");
        assertEq(limitBps, phase2LimitBps, "Phase 2 limit bps mismatch");
        assertEq(cooldown, phase2Cooldown, "Phase 2 cooldown mismatch");
        assertEq(penaltyBps, phase2PenaltyBps, "Phase 2 penalty bps mismatch");
    }

    function test_GetPhaseConfig_Phase3() public view {
        (uint256 duration, uint256 limitBps, uint256 cooldown, uint256 penaltyBps) = antiBotHook.getPhaseConfig(3);

        assertEq(duration, 0, "Phase 3 should have 0 duration");
        assertEq(limitBps, 0, "Phase 3 should have 0 limit bps");
        assertEq(cooldown, 0, "Phase 3 should have 0 cooldown");
        assertEq(penaltyBps, 0, "Phase 3 should have 0 penalty bps");
    }

    /* ══════════════════════════════════════════════════════════════════
                        HOOK PERMISSIONS TESTS
    ══════════════════════════════════════════════════════════════════ */

    function test_HookPermissions() public view {
        Hooks.Permissions memory permissions = antiBotHook.getHookPermissions();

        assertFalse(permissions.beforeInitialize, "Should not have beforeInitialize permission");
        assertTrue(permissions.afterInitialize, "Should have afterInitialize permission");
        assertFalse(permissions.beforeAddLiquidity, "Should not have beforeAddLiquidity permission");
        assertFalse(permissions.afterAddLiquidity, "Should not have afterAddLiquidity permission");
        assertFalse(permissions.beforeRemoveLiquidity, "Should not have beforeRemoveLiquidity permission");
        assertFalse(permissions.afterRemoveLiquidity, "Should not have afterRemoveLiquidity permission");
        assertTrue(permissions.beforeSwap, "Should have beforeSwap permission");
        assertFalse(permissions.afterSwap, "Should not have afterSwap permission");
        assertFalse(permissions.beforeDonate, "Should not have beforeDonate permission");
        assertFalse(permissions.afterDonate, "Should not have afterDonate permission");
        assertFalse(permissions.beforeSwapReturnDelta, "Should not have beforeSwapReturnDelta permission");
        assertFalse(permissions.afterSwapReturnDelta, "Should not have afterSwapReturnDelta permission");
        assertFalse(permissions.afterAddLiquidityReturnDelta, "Should not have afterAddLiquidityReturnDelta permission");
        assertFalse(
            permissions.afterRemoveLiquidityReturnDelta, "Should not have afterRemoveLiquidityReturnDelta permission"
        );
    }

    /* ══════════════════════════════════════════════════════════════════
                        BOT ATTACK SIMULATION TESTS
    ══════════════════════════════════════════════════════════════════ */

    function test_BotAttack_RapidSwaps() public {
        vm.deal(bot1, 10 ether);
        vm.startPrank(bot1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        for (uint256 i = 0; i < 10; i++) {
            swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        }

        assertGt(antiBotHook.addressSwappedAmount(address(swapRouter)), 0, "SwapRouter should have swapped");

        uint256 cooldownEnd = antiBotHook.getUserCooldownEnd(address(swapRouter));
        assertGt(cooldownEnd, block.number, "SwapRouter should have active cooldown");

        vm.stopPrank();
    }

    function test_BotAttack_LargeSwaps() public {
        vm.deal(bot1, 10 ether);
        vm.startPrank(bot1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 1 ether}(key, params, testSettings, ZERO_BYTES);

        assertGt(antiBotHook.addressSwappedAmount(address(swapRouter)), 0, "SwapRouter should have swapped");

        vm.stopPrank();
    }

    function test_BotAttack_MultipleBots() public {
        vm.deal(bot1, 10 ether);
        vm.deal(bot2, 10 ether);

        uint256 swapAmount = 0.001 ether;

        vm.startPrank(bot1);
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: swapAmount}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        vm.startPrank(bot2);
        swapRouter.swap{value: swapAmount}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        assertGt(
            antiBotHook.addressSwappedAmount(address(swapRouter)),
            swapAmount,
            "SwapRouter should have accumulated swaps"
        );
    }

    /* ══════════════════════════════════════════════════════════════════
                        EDGE CASE TESTS
    ══════════════════════════════════════════════════════════════════ */

    function test_SwapBeforeInitialize() public {
        bytes memory creationCode = type(TokenLaunchHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            manager,
            phase1Duration,
            phase2Duration,
            phase1LimitBps,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );

        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);
        (, bytes32 salt) = HookMiner.find(address(this), flags, creationCode, constructorArgs);

        TokenLaunchHook newHook = new TokenLaunchHook{salt: salt}(
            manager,
            phase1Duration,
            phase2Duration,
            phase1LimitBps,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );

        PoolKey memory newKey = PoolKey({
            currency0: ethCurrency,
            currency1: tokenCurrency,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: newHook
        });

        vm.deal(user1, 1 ether);
        vm.startPrank(user1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectRevert(TokenLaunchHook.PoolNotInitialized.selector);
        swapRouter.swap{value: 0.001 ether}(newKey, params, testSettings, ZERO_BYTES);

        vm.stopPrank();
    }

    function test_ZeroAmountSwap() public {
        vm.deal(user1, 1 ether);
        vm.startPrank(user1);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: 0, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectRevert(IPoolManager.SwapAmountCannotBeZero.selector);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        vm.stopPrank();
    }

    function test_GetCurrentPhase_BeforeInitialize() public {
        bytes memory creationCode = type(TokenLaunchHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            manager,
            phase1Duration,
            phase2Duration,
            phase1LimitBps,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );

        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);
        (, bytes32 salt) = HookMiner.find(address(this), flags, creationCode, constructorArgs);

        TokenLaunchHook newHook = new TokenLaunchHook{salt: salt}(
            manager,
            phase1Duration,
            phase2Duration,
            phase1LimitBps,
            phase2LimitBps,
            phase1Cooldown,
            phase2Cooldown,
            phase1PenaltyBps,
            phase2PenaltyBps
        );

        assertEq(newHook.getCurrentPhase(), 0, "Phase should be 0 before initialize");
    }

    /* ══════════════════════════════════════════════════════════════════
                        COMPREHENSIVE SCENARIO TESTS
    ══════════════════════════════════════════════════════════════════ */

    function test_Comprehensive_LaunchScenario() public {
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(bot1, 10 ether);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.startPrank(user1);
        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        vm.startPrank(bot1);
        for (uint256 i = 0; i < 5; i++) {
            swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        }
        vm.stopPrank();

        vm.startPrank(user2);
        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        vm.roll(block.number + phase1Duration + 1);

        vm.startPrank(user1);
        swapRouter.swap{value: 0.002 ether}(key, params, testSettings, ZERO_BYTES);
        vm.stopPrank();

        vm.roll(block.number + phase2Duration + 1);

        vm.startPrank(user1);
        for (uint256 i = 0; i < 10; i++) {
            swapRouter.swap{value: 0.01 ether}(key, params, testSettings, ZERO_BYTES);
        }
        vm.stopPrank();

        assertEq(antiBotHook.getCurrentPhase(), 3, "Should be in phase 3");
    }

    function test_Comprehensive_CooldownAndLimitInteraction() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.001 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);
        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);

        vm.roll(block.number + phase1Cooldown + 1);

        swapRouter.swap{value: 0.001 ether}(key, params, testSettings, ZERO_BYTES);

        assertGt(antiBotHook.addressSwappedAmount(address(swapRouter)), 0, "SwapRouter should have swapped");

        vm.stopPrank();
    }
}
