# Tip Jar

Contracts for an ETH tip jar on **Sepolia (chain ID 11155111)**, with the fixed-supply **Tip Jar (TIPS)** launch token. This contribution contains implementation, tests, vendored dependencies, and ABI exports. The separate manifest and independent review assignments precede release; services subsequently publish to GitHub, attest, admit, deploy, and hand off to the IPFS frontend workflow.

## Build and test

With Foundry and Solidity **0.8.26** installed:

```sh
forge build
forge test
forge fmt --check
```

The compiler version, Cancun EVM target, optimizer settings, and `bytecode_hash = "none"` are pinned in [foundry.toml](foundry.toml). Dependencies are ordinary files under `lib/`; no package installation, submodule, RPC, environment variables, FFI, or filesystem cheatcode permissions are required. The compiler itself is supplied by the execution environment, not vendored. Dependency versions, licenses, and provenance are in [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md).

## Behavior and assumptions

- Anyone can call `TipJar.tip(message)` with **at least 1 wei**, or send ETH with empty calldata for an empty-message tip. Every accepted tip emits `Tip(sender, amount, message)` and increments `totalTipped` by the exact ETH amount. There are no application fees or token requirements; senders still pay network gas.
- Messages are optional, public, valid UTF-8, and limited to **140 Unicode scalar values (code points)**. Multi-byte characters count once. Combining marks and components of joined emoji count separately; no Unicode normalization occurs. Malformed UTF-8 and longer messages revert. This interpretation avoids treating a four-byte emoji as four characters.
- Only the immutable `owner` can call `withdraw()`. It sends the **entire current ETH balance to that same owner address**. An empty jar reverts. A failed payment rolls back the transaction and retains the funds for a retry. Tips and withdrawals are blocked during the payment callback.
- `totalTipped` is cumulative, in wei, and never decreases on withdrawal. ETH forced into the address without executing code is withdrawable but is not a recorded tip, emits no event, and does not increase this counter. The current balance and lifetime tips are different quantities.
- Tips are gifts: no refunds, per-donor claims, deadlines, or rounds. The owner may withdraw at any time. There is no owner replacement, renunciation, pause, proxy, upgrade, arbitrary call, or token recovery function. Sending ERC-20 tokens to the jar can strand them.
- Normal wallet transactions should estimate gas. A contract sending ETH must forward enough gas for storage updates and event emission; Solidity's fixed-stipend `transfer`/`send` is insufficient. Unknown nonempty calldata reverts.

`LaunchToken` is a standard OpenZeppelin ERC-20 named **Tip Jar**, symbol **TIPS**, with **18 decimals** and exactly **1,000,000,000 tokens (10^27 minor units)** minted once to its deploying caller. It has no constructor arguments and exposes no mint, burn, ownership, fee, blocklist, pause, or upgrade operation. The brief requests no conflicting token behavior. TIPS does not represent a claim on donations.

## Deployment parameters and responsibilities

Both constructors are nonpayable and fully configure their contracts. No initialization call is needed.

| Artifact | Constructor arguments | Responsibility |
| --- | --- | --- |
| `src/LaunchToken.sol:LaunchToken` | None | Factory receives the entire supply and performs policy distribution. |
| `src/TipJar.sol:TipJar` | `address initialOwner` = `$owner` | The policy's requester controls withdrawals and receives the ETH. Must be nonzero. |

The brief's “owner (deployer)” means the requester behind the launch. In the factory workflow, the actual constructor caller is `ProjectFactory`, which cannot operate the jar. **The manifest must pass `$owner`, not the factory address, as `initialOwner`.** For direct deployment, pass the intended deployer's address explicitly. The token intentionally uses `msg.sender` for its initial mint, as required by the factory's supply check. The two contracts have no application dependency on each other.

The separate manifest assignment names `LaunchToken` as the launch token and `TipJar` as the application; this contribution does not create `launch.json`. Before admission, independently review the actual source and manifest, especially the resolved owner argument. Policy and signed artifact linkage belong to the services. A wrong owner address, or a contract owner unable to initiate withdrawals or receive ETH, can permanently lock funds. The constructor checks nonzero only; services must validate the chosen wallet's capabilities and control before deployment. No wallet or deployed address is hard-coded here.

The factory, not these contracts, allocates supply: 2% to accepted contributors, 8% to paired seats at admission, and 90% to the requester including the liquidity allocation (80% of total supply by default). The factory supplies its Merkle distributor and pool initialization guard. No application constructor receives, transfers, or approves launch tokens.

Pool configuration belongs to the manifest/services: native ETH is the default pair, unless the approved policy chooses the network pair token. Canonical admission fields are fee `3000`, tick spacing `60`, and initial price `79228162514264337593543950336`; the service derives the effective opening price from pinned policy. The pool's actual trading fee comes from the network's LaunchFees contract (1.25% by default: 1% to the launch payer and 0.25% to IMD). There is no swap fee logic in either project contract. Use the exact pool key in the deployment handoff.

Services own source publication, attestations, admission, deployment, address and deployment-block handoff, and explorer verification. The owner owns wallet security and withdrawal transactions. The frontend contributor owns the one-page UI, event indexing, wallet integration, and IPFS publication. No transaction broadcasting or private keys are needed to build or test this contribution.

## Integration and review

Machine-readable ABIs are [docs/abi/TipJar.json](docs/abi/TipJar.json) and [docs/abi/LaunchToken.json](docs/abi/LaunchToken.json). [docs/ABI.md](docs/ABI.md) describes the calls, events, errors, and frontend integration rules.

Tests cover tips and exact events, ASCII/Unicode boundaries and invalid encodings, unauthorized/empty/failed withdrawals, contract wallets, callback reentrancy, forced-balance accounting, token transfers and allowances, constructor-only CREATE2 deployment, runtime size/opcode constraints, and stateful conservation. Fuzz tests run 256 cases per function; the invariant campaign runs 128 sequences of 64 calls. All tests use local, isolated state and no shared environment configuration.

[docs/SECURITY.md](docs/SECURITY.md) records the implementation's trust assumptions and review handoff. These local checks are not an independent security review. The requested independent contributor review must inspect the accepted source and final manifest before launch.
