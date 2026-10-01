# Vendored dependencies

These dependencies are delivered as ordinary source files, with no submodules or network installation step. Project contracts pin Solidity 0.8.26; all vendored Solidity used by the build supports that compiler.

| Dependency | Upstream release | Included files | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | [v5.1.0](https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.1.0) | ERC20, IERC20, IERC20Metadata, IERC20Errors interface file, Context, ReentrancyGuard, LICENSE | MIT |
| forge-std | [v1.9.7](https://github.com/foundry-rs/forge-std/releases/tag/v1.9.7) | Complete `src/` tree and both license files | MIT / Apache-2.0 |

Selected files are copied unchanged from upstream tag archives. No dependency deployment scripts, package managers, compiler binaries, or repository metadata are required.

Archive URLs and SHA-256 digests:

```text
https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.1.0
8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686

https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94
```

Licenses are retained at `lib/openzeppelin-contracts/LICENSE`, `lib/forge-std/LICENSE-MIT`, and `lib/forge-std/LICENSE-APACHE`.
