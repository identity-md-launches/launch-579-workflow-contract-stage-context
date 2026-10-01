# Security assumptions and independent review handoff

This is implementation documentation, not an independent audit or launch approval. The approved workflow requests a separate contributor review of the accepted contracts and final `launch.json` before launch. That reviewer should return findings without modifying source or the manifest. Services own policy linkage and signed artifact linkage; concrete constructor or authorization conflicts remain review findings.

## Trust and custody

The immutable jar owner can withdraw every wei at any time, including unrecorded forced ETH. Donors have no refund claim. There are no other privileged roles or upgrade paths. Owner compromise exposes all current and future tips. Loss of the owner key, a wrong constructor argument, or an owner contract that cannot call `withdraw()` or accept ETH may lock the funds permanently. There is no recovery role or ability to redirect withdrawals.

The requester is passed explicitly as `$owner` because the deploying factory cannot exercise owner powers. The launch token deliberately mints its entire fixed supply to that factory. The jar never calls or approves the token, and token holders have no rights over donations.

## Implementation checks

| Area | Design and local evidence |
| --- | --- |
| Authorization | Immutable explicit owner; unauthorized requester/factory/deployer cases exercised. |
| ETH accounting | No per-user debt; actual balance is withdrawn once, lifetime total persists. Fuzz and stateful tests independently track sent and withdrawn ETH. Forced ETH is a separately documented balance source. |
| External call | OpenZeppelin's storage reentrancy guard is entered before payment. All three value-changing entry points use the same guard. The low-level payment result is checked, and failure reverts all effects. |
| Callback failures | Tests cover rejection, withdrawal reentry, both tip entry points during callbacks, propagated failure, and retry after rollback. A contract receiver requiring more than 2,300 gas succeeds. |
| Input bounds | Positive tips, nonzero owner, and at most 560 UTF-8 bytes / 140 scalar values. Tests include encoding boundary values, invalid continuation bytes, overlong encodings, truncation, surrogates, and out-of-range values. |
| Token | Unmodified OpenZeppelin ERC-20 behavior with one constructor mint, exact transfers, fixed 18 decimals, and no exposed admin/mint path. Allowance success, failure, revocation, and infinite allowance behavior are tested. |
| Deployment | Tests exercise constructor-only CREATE2 deployment from a factory, nonpayable constructor rejection, unchanged factory supply, and runtime size/forbidden opcode scans. No delegatecall, callcode, selfdestruct, initialization, or proxy is used by production contracts. |
| Frontend | Events contain arbitrary public text. The UI must render text safely, count Unicode code points, and handle reorgs and RPC pagination. Frontend correctness is outside this contract contribution. |

`forge build` may report `reentrancy-eth` at the owner's payment because the guard's reset occurs after the call. The guard has already set its entered state before that call; callback tests assert the specific guard error on all three entry points. It may also report `require-revert-in-loop` in the bounded UTF-8 validator. Those reverts deliberately reject invalid messages atomically; they do not iterate over external users or make external calls.

The UTF-8 validator is project-specific code and deserves independent attention. “Character” means Unicode scalar value, not a user-perceived grapheme cluster. A successful empty-calldata donation requires enough gas for the guard, counter, and event; fixed-stipend transfers are not supported. An attacker can publish offensive messages by paying for a tip, but cannot alter another tip or withdraw funds. Logs are public and have no deletion mechanism.

## Validation and remaining release work

Local tooling: Foundry build, unit/fuzz/stateful tests, and formatting checks with solc 0.8.26. The protected input tests establish deployment/token floors; their service-provided environment and final manifest are not available in this source assignment. Local factory and token tests exercise the corresponding constraints without reading or setting environment variables. Slither, Mythril, fork tests, real-chain transactions, and an independent audit have not been run here.

Before release, the independent contributor must inspect the final source and actual manifest arguments, including recipient authority. Services must resolve and verify Sepolia's factory/network configuration, validate the policy owner, publish and attest source, admit the policy-linked artifacts, deploy, and provide verified addresses and deployment blocks to the frontend. Tests alone do not establish these service outcomes.
