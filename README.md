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
- opens vim on `main.rs`, whatever `$EDITOR` says, since the run-on-save and
  `<leader>r` bindings live in vim. Set `SCRATCH_EDITOR` to use another
  editor on purpose. Inside tmux it also opens a pane beside vim that
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

## When it isn't what you expect

- **nano (or another editor) opens instead of vim.** Before paulgsc/scratch#2,
  `scratch` opened `$EDITOR`, and NixOS sets `EDITOR=nano` by default. It now
  always opens vim, because the run-on-save and `<leader>r` bindings live in
  vim (paulgsc/dotfiles `pkgs/vim/scratch.vim`); `SCRATCH_EDITOR` picks another
  editor on purpose. If nano still opens, your machine is running a copy of
  `scratch` from before that change: see the next point.
- **A change pushed here hasn't reached you.** `prefix S` runs
  `nix develop github:paulgsc/scratch#scratchpad`, and Nix reuses its last
  fetch of an unlocked `github:` flake for `tarball-ttl` (one hour by
  default) before it looks again. To take the newest `main` now:

  ```
  nix develop --refresh github:paulgsc/scratch#scratchpad -c true
  ```

  The toolchain itself moves only when `flake.lock` does, never on a refresh.
