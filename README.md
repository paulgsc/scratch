# scratch

A throwaway Rust scratchpad: write a `fn main` in vim, get rustc, clippy and
rust-analyzer feedback, run it. There's no crate, no `Cargo.toml` and nothing to
clean up.

```sh
nix develop github:paulgsc/scratch -c scratch
```

That one command (bound to `prefix S` in tmux by paulgsc/dotfiles):

- makes a directory under `$XDG_RUNTIME_DIR`, which is tmpfs. It falls back
  to `/dev/shm`, then `$TMPDIR`.
- writes `main.rs` and a `rust-project.json`, so rust-analyzer works with no
  `Cargo.toml`.
- opens vim on `main.rs`. Inside tmux it also opens a pane beside vim that
  compiles, lints and runs the file on every save.

Quit vim or close the window, and the directory is deleted. **Nothing is
kept.** Copy anything worth keeping somewhere else first.

## Commands

| | |
|---|---|
| `scratch` | the above |
| `scratch run FILE [ARGS]` | compile with rustc + clippy lints (edition 2024), then run it if it compiles. The binary goes to a temp dir that is removed afterwards. Works on any `.rs` with a `main`. |
| `scratch watch [PATH]` | `scratch run` again on every save of a `.rs` file beside PATH. A save restarts a program that is still running. |
| `scratch check FILE\|-` | compile and lint only, printing rustc's JSON diagnostics (what the editor runs). |

New `.rs` files in a scratch dir are picked up too. `:e other.rs` in vim
makes it a crate of its own on its first save. With no FILE, the watch pane
runs whichever `.rs` you saved last.

`clippy-driver` is rustc with clippy's lints added, so one pass compiles,
lints and links. Extra lints come from `SCRATCH_CLIPPY`, for example
`SCRATCH_CLIPPY="-W clippy::pedantic"`. Another edition comes from
`SCRATCH_EDITION`. Only `std` is available: there are no crates.io
dependencies.

## The toolchain

The toolchain lives only in this flake's dev shell
(`devShells.<system>.scratchpad`, also `default`), never in NixOS or home. It
is the stable Rust from [oxalica/rust-overlay](https://github.com/oxalica/rust-overlay),
pinned by `flake.lock`, with clippy, rustfmt, rust-analyzer and rust-src, plus
`cc` as the linker and `watchexec`. `nix flake update` moves it.

`nix flake check` builds `scratch` and compiles and runs a hello world with it.
