# Contract API and frontend handoff

The JSON files under `docs/abi/` are ABI arrays generated with the pinned compiler. Regenerate after source changes:

```sh
forge inspect src/TipJar.sol:TipJar abi --json > docs/abi/TipJar.json
forge inspect src/LaunchToken.sol:LaunchToken abi --json > docs/abi/LaunchToken.json
```

## TipJar

Constructor: `constructor(address initialOwner)`, **nonpayable**. The launch manifest supplies `$owner`; zero is rejected. Ownership is immutable.

| Method | Mutability | Meaning |
| --- | --- | --- |
| `tip(string message)` | payable | Send positive ETH and a valid UTF-8 message of at most 140 code points. |
| Empty calldata | payable receive | Send positive ETH as a tip with an empty message. |
| `withdraw()` | nonpayable | Owner sends the entire current balance to itself. |
| `owner()` | view → address | Immutable withdrawal authority and recipient. |
| `totalTipped()` | view → uint256 | Lifetime recorded tip amount in wei, unaffected by withdrawals. |
| `MAX_MESSAGE_CHARACTERS()` | view → uint256 | Returns 140. |

Events:

```solidity
event Tip(address indexed sender, uint256 amount, string message);
event Withdrawal(address indexed owner, uint256 amount);
```

`amount` is in wei. Messages are event data, not contract storage. Events are emitted only for successful transactions. A reverted withdrawal does not persist a `Withdrawal` event. There is no on-chain array of recent tips.

| Custom error | Meaning |
| --- | --- |
| `InvalidOwner()` | Constructor owner is zero. |
| `NotOwner()` | Withdrawal caller is not the configured owner. |
| `ZeroTip()` | ETH tip value is zero. |
| `MessageTooLong()` | Message exceeds the code-point limit or maximum possible UTF-8 byte length. |
| `InvalidUTF8()` | Malformed, truncated, overlong, surrogate, or out-of-range encoding. |
| `NothingToWithdraw()` | Current ETH balance is zero. |
| `WithdrawalFailed()` | Owner's receiving call failed; funds remain in the jar. |
| `ReentrancyGuardReentrantCall()` | Tip/receive/withdraw was called from a withdrawal callback. |

Malformed ABI calldata and unknown selectors also revert; callers should not assume every failure has a custom error. Multiple invalid inputs need not have a stable error precedence.

## LaunchToken

Constructor: `constructor()`, **nonpayable**. Standard ERC-20 methods: `name()`, `symbol()`, `decimals()`, `totalSupply()`, `balanceOf(address)`, `allowance(address,address)`, `transfer(address,uint256)`, `approve(address,uint256)`, and `transferFrom(address,address,uint256)`. Write methods return `bool` on success and otherwise revert. `Transfer` and `Approval` follow ERC-20; errors use OpenZeppelin's IERC20Errors definitions included in the exported ABI.

The initial `Transfer(address(0), deployer, 10^27)` represents the only mint. Zero-value transfers are valid; zero recipients are rejected. Finite allowances decrease with `transferFrom`; maximum allowances do not. OpenZeppelin v5 does not emit `Approval` when spending allowance through `transferFrom`, so read `allowance()` for current authorization. Token approvals are unnecessary for ETH tips. When replacing an existing token allowance, revoke it first and wait for confirmation to avoid the standard allowance replacement race.

## One-page frontend requirements

1. Take chain ID, deployed addresses, ABIs, deployment block, and any pool key from the service handoff. Enforce Sepolia and verify the selected contract address before submitting a transaction.
2. Read `Tip` logs from the jar starting at its deployment block, paginating within RPC limits. Order by `(blockNumber, transactionIndex, logIndex)` and display the newest 20. Deduplicate with transaction hash and log index, and reconcile removed logs/reorganizations; a timestamp alone is not an ordering key.
3. Read `totalTipped()` for lifetime donations, not the sum of the last 20 events. If showing the available withdrawal amount, read the current ETH balance separately. Query values at a consistent block when possible.
4. Submit `tip(message)` with a positive ETH `value`, estimate gas, and wait for a successful receipt. An empty message is valid. Validate well-formed Unicode and count code points (for example `Array.from(message).length` after well-formedness validation), not UTF-16 code units or UTF-8 bytes. Reject unpaired surrogates before text encoding. No normalization is done by the contract.
5. Render untrusted messages as text, never HTML or executable URLs. They are permanent public data; control characters and combining marks are valid and may need safe display handling.
6. Show **Withdraw** only when the connected wallet equals `owner()` on the correct chain; call `withdraw()` without value or recipient arguments. The on-chain access check is authoritative. For smart-wallet owners, route the call through that owner wallet. Refresh balance and cumulative totals after confirmation.

The source assignment supplies this interface contract; frontend implementation and IPFS hosting follow service deployment.
