// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {BaseScript} from "./Base.s.sol";

import {TokenLaunchHook} from "../src/TokenLaunchHook.sol";

/// @notice Mines the address and deploys the TokenLaunchHook contract
contract DeployHookScript is BaseScript {
    // CREATE2 factory address for deploying hooks with specific flags
    // address constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Default configuration for token launch protection
    uint256 constant PHASE1_DURATION = 100; // blocks
    uint256 constant PHASE2_DURATION = 200; // blocks
    uint256 constant PHASE1_LIMIT_BPS = 100; // 1% of initial liquidity
    uint256 constant PHASE2_LIMIT_BPS = 300; // 3% of initial liquidity
    uint256 constant PHASE1_COOLDOWN = 5; // blocks
    uint256 constant PHASE2_COOLDOWN = 3; // blocks
    uint256 constant PHASE1_PENALTY_BPS = 500; // 5% penalty
    uint256 constant PHASE2_PENALTY_BPS = 200; // 2% penalty

    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_INITIALIZE_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(
            poolManager,
            PHASE1_DURATION,
            PHASE2_DURATION,
            PHASE1_LIMIT_BPS,
            PHASE2_LIMIT_BPS,
            PHASE1_COOLDOWN,
            PHASE2_COOLDOWN,
            PHASE1_PENALTY_BPS,
            PHASE2_PENALTY_BPS
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(TokenLaunchHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        TokenLaunchHook hook = new TokenLaunchHook{salt: salt}(
            poolManager,
            PHASE1_DURATION,
            PHASE2_DURATION,
            PHASE1_LIMIT_BPS,
            PHASE2_LIMIT_BPS,
            PHASE1_COOLDOWN,
            PHASE2_COOLDOWN,
            PHASE1_PENALTY_BPS,
            PHASE2_PENALTY_BPS
        );
        vm.stopBroadcast();
        require(address(hook) == hookAddress, "DeployHookScript: Hook Address Mismatch");
    }
}
