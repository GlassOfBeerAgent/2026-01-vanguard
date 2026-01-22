# Vanguard

- Starts: January 29, 2025 Noon UTC
- Ends: February 05, 2025 Noon UTC

- nSLOC: ~273

[//]: # (contest-details-open)

## About the Project

Vanguard is a Uniswap V4 hook implementation that provides anti-bot protection for token launches. The protocol implements a phased fee structure to prevent manipulation during the initial launch period, with configurable limits, cooldowns, and penalties for excessive selling.

The hook intercepts swap operations and enforces dynamic fees based on the launch phase:
- Phase 1: Strict limits on sell amounts with high penalties for violations
- Phase 2: Relaxed limits with moderate penalties
- Post-launch: Standard Uniswap fees apply

This creates a fair launch environment that protects early participants while allowing natural price discovery.

[Documentation](https://github.com/fethallaheth/Vanguard/blob/main/README.md)

[GitHub](https://github.com/fethallaheth/Vanguard)

[Uniswap V4 Docs](https://docs.uniswap.org/contracts/v4/overview)

## Actors

```

There are 2 main actors in this protocol:

1. owner:
RESPONSIBILITIES:

- deploys hook contract with launch parameters (durations, limits, penalties)
- can modify fee parameters via administrative functions
- has full administrative control over launch configuration
- monitors launch progress 


2. swapper:
RESPONSIBILITIES:

- can execute swaps through Uniswap V4 pools utilizing this hook
- must comply with per-block swap limits during launch phases

LIMITATIONS:

- cannot bypass hook-enforced limits and penalties
- cannot modify launch parameters
- subject to pool liquidity constraints
- must use pools that implement the hook


```

## Scope (contracts)


- [TokenLaunchHook](./src/TokenLaunchHook.sol)
- [DeployHookScript](./script/deployLaunchHook.s.sol)

## Compatibilities

```
Compatibilities:

  Blockchains:
      - Any EVM-compatible chain with Uniswap V4
  Tokens:
      - Standard ERC20 tokens
```



[//]: # (getting-started-open)

## Setup

Build:

```
git clone https://github.com/CodeHawks-Contests/2026-01-vanguard.git
cd Vanguard

forge install

forge build 

```

Tests:

```
forge test 
```

Scripts : 

```
forge build --contracts script/deployLaunchHook.s.sol 
```


[//]: # (known-issues-open)

## Known Issues

Known Issues:

- Owner has unrestricted access to modify parameters (consider multi-sig or timelock for production)
- Hook relies on block numbers for phase timing, which may be manipulable on some chains
 