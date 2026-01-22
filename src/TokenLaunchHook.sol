// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

/// @title TokenLaunchHook - A Uniswap V4 Hook to mitigate bot activity during token launches
/// @author ChoasSR (https://x.com/0xlinguin) | (https://github.com/fethallaheth)
contract TokenLaunchHook is BaseHook {
    using LPFeeLibrary for uint24;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    CUSTOM ERRORS                    */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    error PoolNotInitialized();
    error InvalidConstructorParams();
    error DynamicFeeNotEnabled();
    error MustUseDynamicFee();

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                      IMMUTABLE                      */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    uint256 public immutable phase1Duration;
    uint256 public immutable phase2Duration;
    uint256 public immutable phase1LimitBps;
    uint256 public immutable phase2LimitBps;
    uint256 public immutable phase1Cooldown;
    uint256 public immutable phase2Cooldown;
    uint256 public immutable phase1PenaltyBps;
    uint256 public immutable phase2PenaltyBps;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   STATE VARIABLES                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    uint256 public currentPhase;
    uint256 public lastPhaseUpdateBlock;

    uint256 public launchStartBlock;
    uint256 public initialLiquidity;
    uint256 public totalPenaltyFeesCollected;

    mapping(address => uint256) public addressSwappedAmount;
    mapping(address => uint256) public addressLastSwapBlock;
    mapping(address => uint256) public addressTotalSwaps;
    mapping(address => uint256) public addressPenaltyCount;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                     CONSTRUCTOR                     */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    constructor(
        IPoolManager _poolManager,
        uint256 _phase1Duration,
        uint256 _phase2Duration,
        uint256 _phase1LimitBps,
        uint256 _phase2LimitBps,
        uint256 _phase1Cooldown,
        uint256 _phase2Cooldown,
        uint256 _phase1PenaltyBps,
        uint256 _phase2PenaltyBps
    ) BaseHook(_poolManager) {
        if (_phase1Duration == 0 || _phase2Duration == 0) revert InvalidConstructorParams();
        if (
            _phase1LimitBps > 10000 || _phase2LimitBps > 10000 || _phase1PenaltyBps > 10000 || _phase2PenaltyBps > 10000
        ) revert InvalidConstructorParams();
        phase1Duration = _phase1Duration;
        phase2Duration = _phase2Duration;
        phase1LimitBps = _phase1LimitBps;
        phase2LimitBps = _phase2LimitBps;
        phase1Cooldown = _phase1Cooldown;
        phase2Cooldown = _phase2Cooldown;
        phase1PenaltyBps = _phase1PenaltyBps;
        phase2PenaltyBps = _phase2PenaltyBps;
        currentPhase = 0;
        lastPhaseUpdateBlock = 0;
        totalPenaltyFeesCollected = 0;
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                  UNISWAP FUNCTIONS                  */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _afterInitialize(address, PoolKey calldata key, uint160, int24) internal override returns (bytes4) {
        if (!key.fee.isDynamicFee()) {
            revert MustUseDynamicFee();
        }
        launchStartBlock = block.number;
        uint128 liquidity = StateLibrary.getLiquidity(poolManager, key.toId());
        initialLiquidity = uint256(liquidity);
        currentPhase = 1;
        lastPhaseUpdateBlock = block.number;
        return BaseHook.afterInitialize.selector;
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (launchStartBlock == 0) revert PoolNotInitialized();

        if (initialLiquidity == 0) {
            uint128 liquidity = StateLibrary.getLiquidity(poolManager, key.toId());
            initialLiquidity = uint256(liquidity);
        }

        uint256 blocksSinceLaunch = block.number - launchStartBlock;
        uint256 newPhase;
        if (blocksSinceLaunch <= phase1Duration) {
            newPhase = 1;
        } else if (blocksSinceLaunch <= phase1Duration + phase2Duration) {
            newPhase = 2;
        } else {
            newPhase = 3;
        }
        if (newPhase != currentPhase) {
            _resetPerAddressTracking();
            currentPhase = newPhase;
            lastPhaseUpdateBlock = block.number;
        }
        if (currentPhase == 3) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, LPFeeLibrary.OVERRIDE_FEE_FLAG);
        }
        uint256 phaseLimitBps = currentPhase == 1 ? phase1LimitBps : phase2LimitBps;
        uint256 phaseCooldown = currentPhase == 1 ? phase1Cooldown : phase2Cooldown;
        uint256 phasePenaltyBps = currentPhase == 1 ? phase1PenaltyBps : phase2PenaltyBps;
        uint256 swapAmount =
            params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        uint256 maxSwapAmount = (initialLiquidity * phaseLimitBps) / 10000;
        bool applyPenalty = false;
        if (addressLastSwapBlock[sender] > 0) {
            uint256 blocksSinceLastSwap = block.number - addressLastSwapBlock[sender];
            if (blocksSinceLastSwap < phaseCooldown) {
                applyPenalty = true;
            }
        }
        if (!applyPenalty && addressSwappedAmount[sender] + swapAmount > maxSwapAmount) {
            applyPenalty = true;
        }

        addressSwappedAmount[sender] += swapAmount;
        addressLastSwapBlock[sender] = block.number;

        uint24 feeOverride = 0;
        if (applyPenalty) {
            feeOverride = uint24((phasePenaltyBps * 100));
        }
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            feeOverride | LPFeeLibrary.OVERRIDE_FEE_FLAG
        );
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                  INTERNAL FUNCTIONS                 */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    function _resetPerAddressTracking() internal {
        addressSwappedAmount[address(0)] = 0;
        addressLastSwapBlock[address(0)] = 0;
    }

    function getCurrentPhase() public view returns (uint256) {
        if (launchStartBlock == 0) return 0;
        uint256 blocksSinceLaunch = block.number - launchStartBlock;
        if (blocksSinceLaunch < phase1Duration) {
            return 1;
        } else if (blocksSinceLaunch < phase1Duration + phase2Duration) {
            return 2;
        } else {
            return 3;
        }
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    VIEW FUNCTIONS                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    function getUserRemainingLimit(address user) public view returns (uint256) {
        // FIXED: Check actual current phase, not stored state
        uint256 phase = getCurrentPhase();
        if (phase == 3) return type(uint256).max;

        uint256 phaseLimitBps = phase == 1 ? phase1LimitBps : phase2LimitBps;
        uint256 maxSwapAmount = (initialLiquidity * phaseLimitBps) / 10000;
        if (addressSwappedAmount[user] >= maxSwapAmount) return 0;
        return maxSwapAmount - addressSwappedAmount[user];
    }

    function getUserCooldownEnd(address user) public view returns (uint256) {
        // FIXED: Check actual current phase, not stored state
        uint256 phase = getCurrentPhase();
        if (phase == 3) return 0;

        uint256 phaseCooldown = phase == 1 ? phase1Cooldown : phase2Cooldown;
        if (addressLastSwapBlock[user] == 0) return 0;
        uint256 cooldownEnd = addressLastSwapBlock[user] + phaseCooldown;
        if (block.number >= cooldownEnd) return 0;
        return cooldownEnd;
    }

    function getPhaseConfig(uint256 phase)
        public
        view
        returns (uint256 duration, uint256 limitBps, uint256 cooldown, uint256 penaltyBps)
    {
        if (phase == 1) {
            duration = phase1Duration;
            limitBps = phase1LimitBps;
            cooldown = phase1Cooldown;
            penaltyBps = phase1PenaltyBps;
        } else if (phase == 2) {
            duration = phase2Duration;
            limitBps = phase2LimitBps;
            cooldown = phase2Cooldown;
            penaltyBps = phase2PenaltyBps;
        } else {
            duration = 0;
            limitBps = 0;
            cooldown = 0;
            penaltyBps = 0;
        }
    }
}
