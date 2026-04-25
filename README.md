# FCM — Flow Credit Markets

Building DeFi Strategies as easy as Lego. Strategies are written by combining small, easy to use, audited **blocks** — wrappers around lending protocols, price oracles, swappers, and more... A strategy is the choice of which blocks to combine and how — the heavy lifting lives in the blocks. Users never invest in a strategy directly; they invest in a `Profile` of a strategy and hold a `Vault` for it.

Three layers, in order of abstraction:

- **Strategy** — a contract like `LendingStrategyV1` that defines the logic (deposit, withdraw, rebalance) but is generic over the specific tokens, blocks, and risk parameters. New strategies ship as new contracts.
- **Profile** — a configured instance of a strategy: a `Profile` struct value that pins specific tokens, blocks, and parameters. Registered once with `FlowYieldVaultsRegistry` under a name (e.g. `pyusd-flow-v1`). Profiles are what users actually invest in.
- **Vault** — a per-user resource minted from a Profile, held in the user's account storage. Many Vaults of the same Profile coexist — one per user. The deposit/withdraw/rebalance logic runs against the user's Vault.

## Lifecycle

Every block and every strategy has one of four statuses. The status controls which kinds of changes are allowed to it:

| Status | Meaning |
|---|---|
| **Under development** | API may still change without notice. Not safe for production profiles to depend on; use only by other components under development. |
| **Live** | Has been fully reviewed and audited. Frozen interface and storage layout. Only critical security bug-fixes are applied. |
| **Deprecated** | Existing dependents continue to work; no new profiles should depend on it. |
| **Dead** | No longer functional — e.g. an oracle provider stopped publishing price data. |

Multiple versions of the same block or strategy can hold **Live** at the same time. When `MOREV2` ships, `MOREV1` can stay Live. Deprecation only happens when there is a clear reason to stop using a contract.

## Blocks

| Contract | Status | Depends on | Notes |
|---|---|---|---|
| `LimitedAccessV1` | Under development | — | `Manager` resource — per-address allowance book. Strategies hold one Manager per Profile to gate Vault creation during early access; multiple Managers can coexist independently. |
| `MOREV1` | Under development | — | Wraps the MORE Markets lending pool on Flow EVM, including the bridge round-trip so callers work in `FungibleToken.Vault`s instead of EVM units. |
| `MOREOracleV1` | Under development | — | Reads USD prices from MORE Markets' on-chain oracle and returns them as `UFix64`. |
| `EventCallbackV1` | Under development | — | Polls a `checkFunction` and invokes a registered `callbackFunction` once it returns true — e.g. fires a rebalance when a lending position's health drops below a threshold. |

### Swappers

Swap blocks living in `cadence/contracts/blocks/swappers/`. Each is a thin wrapper around its underlying liquidity venue. They don't share an interface — strategies pin a concrete swapper struct per slot. Each one exposes `inType()`, `outType()`, `quoteIn`, `quoteOut`, `swap`, `swapBack`, plus `swapExactOut(maxIn: &Vault, desiredOut)` which pulls only what's needed and leaves the rest in `maxIn`.

| Contract | Status | Backing protocol | Notes |
|---|---|---|---|
| `UniswapV2SwapperV1` | Under development | Uniswap-V2 (PunchSwap-style) router | Single-pool or multi-hop EVM swaps. Quotes via `getAmountsIn`/`getAmountsOut`; exact-out via `swapTokensForExactTokens`. |
| `UniswapV3SwapperV1` | Under development | Uniswap-V3 (KittyPunch) router + quoter | Single- or multi-hop EVM swaps with fee-tier path. Quotes via the V3 quoter; exact-out via `exactOutput`. |
| `ERC4626SwapperV1` | Under development | bare ERC4626 vault | "Swap" assets ↔ shares via `deposit`/`mint`/`redeem`. Quotes via `previewDeposit`/`previewMint`/`previewRedeem`/`previewWithdraw`. `swapBack`/`exactOut` revert if the vault doesn't settle redeems synchronously. |
| `MorphoERC4626SwapperV1` | Under development | Morpho ERC4626 vault | Same shape as `ERC4626SwapperV1`; `isReversed` flips inType/outType so the strategy can hold shares as the input side. Exact-out shares→assets uses `withdraw(assets, …)`. |

## Strategies

| Strategy | Status | Depends on | Notes |
|---|---|---|---|
| `LendingStrategyV1` | Under development | `MOREV1`, `MOREOracleV1`, `LimitedAccessV1`, `UniswapV3SwapperV1` | Profiles supply collateral, borrow up to a configurable health-factor target, swap the debt into a yield-bearing token through a configured swapper, hold it. `withdraw` performs the inverse pro-rata unwind. Vault creation is gated by a `LimitedAccessV1` pass capability — the strategy consumes one allowance per Vault minted. |

## Registry

`FlowYieldVaultsRegistry` is just a list of **Profiles**. An admin registers a Profile under a name (e.g. `pyusd-flow-v1`); from then on, frontends and data tooling list it through the registry instead of tracking individual contract addresses. The registry never mints Vaults — that happens on the strategy contract directly (e.g. `LendingStrategyV1.createVault(profile:, position:)`).
