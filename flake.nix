{
  description = "scratch: a throwaway Rust scratchpad. rustc, clippy and rust-analyzer on a file in tmpfs, gone when you close it.";

  inputs = {
    # Same channel as paulgsc/dotfiles, so the shell shares its store paths.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    perSystem = system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [rust-overlay.overlays.default];
      };

      # Stable, pinned by flake.lock (`nix flake update rust-overlay` moves it).
      # rust-src is what rust-analyzer reads std from; see scratch.sh.
      toolchain = pkgs.rust-bin.stable.latest.minimal.override {
        extensions = ["clippy" "rustfmt" "rust-analyzer" "rust-src"];
      };

      scratch = pkgs.writeShellApplication {
        name = "scratch";
        # tmux is deliberately not here: `scratch` uses the tmux you are
        # already inside, and falls back to vim alone without one.
        runtimeInputs = [
          toolchain
          pkgs.stdenv.cc # the linker rustc calls (`cc`)
          pkgs.watchexec
          pkgs.coreutils
          pkgs.findutils
          pkgs.diffutils
        ];
        text = builtins.readFile ./scratch.sh;
      };

      shell = pkgs.mkShell {
        packages = [toolchain pkgs.stdenv.cc pkgs.watchexec scratch];
      };
    in {
      packages = {
        inherit scratch;
        default = scratch;
      };
      devShells = {
        scratchpad = shell;
        default = shell;
      };
      checks.scratch = pkgs.runCommand "scratch-smoke" {nativeBuildInputs = [scratch];} ''
        export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR
        printf 'fn main() { println!("ok {}", 6 * 7); }\n' > hello.rs
        scratch run hello.rs | tee out
        grep -q 'ok 42' out
        touch $out
      '';

      formatter = pkgs.alejandra;
    };
    each = attr: forAllSystems (system: (perSystem system).${attr});
  in {
    packages = each "packages";
    devShells = each "devShells";
    checks = each "checks";
    formatter = each "formatter";
  };
}
