# scratch: a throwaway Rust scratchpad.  See README.md.
#
#   scratch               new scratch dir in tmpfs, vim on main.rs, and (inside
#                         tmux) a pane beside it that recompiles on every save.
#                         Quit vim (or close the window) and the dir is gone.
#   scratch run FILE      compile FILE with rustc + clippy lints, run it on success
#   scratch watch [PATH]  `scratch run` again on every save of a .rs in PATH's dir
#                         (PATH a dir: the .rs saved last)
#   scratch check FILE|-  compile + lint only (- reads stdin), rustc's JSON
#                         diagnostics on stderr: the editor's lint as you type
#
# Nothing is written outside one directory under $XDG_RUNTIME_DIR (tmpfs), and
# every command that makes one removes it on exit.

EDITION="${SCRATCH_EDITION:-2024}"
# Extra clippy flags, e.g. SCRATCH_CLIPPY="-W clippy::pedantic".
read -r -a CLIPPY_FLAGS <<<"${SCRATCH_CLIPPY:-}"
MARKER=.scratch

usage() {
  cat <<'USAGE'
scratch               new scratch dir in tmpfs, vim on main.rs and (inside tmux)
                      a pane beside it that recompiles, lints and runs on save;
                      quit vim or close the window and the dir is gone
scratch run FILE|DIR  compile with rustc + clippy lints, run on success
                      (DIR: the .rs saved last)
scratch watch [PATH]  `scratch run PATH` again on every save of a .rs beside it
scratch check FILE|-  compile + lint only, rustc JSON diagnostics (for editors)
USAGE
}

die() {
  echo "scratch: $*" >&2
  exit 2
}

# A fresh directory on tmpfs.  $XDG_RUNTIME_DIR is per-user tmpfs on systemd
# machines; /dev/shm is tmpfs nearly everywhere else; $TMPDIR is the last resort.
mkscratch() {
  local base
  for base in "${XDG_RUNTIME_DIR:-}" /dev/shm "${TMPDIR:-/tmp}"; do
    if [ -n "$base" ] && [ -d "$base" ] && [ -w "$base" ]; then
      mktemp -d "$base/scratch.XXXXXX"
      return
    fi
  done
  die "no writable temp directory"
}

# rust-analyzer with no Cargo.toml: one crate per top-level .rs file, std from
# the toolchain's rust-src.  Rewritten (only when it changes) by every
# `scratch run`, so a new file in the dir is a crate by its next save.
# https://rust-analyzer.github.io/book/non_cargo_based_projects.html
# No check-on-save runnable here: rust-analyzer gives the as-you-type analysis
# and the editor runs `scratch check -` for rustc + clippy itself
# (paulgsc/dotfiles pkgs/vim/scratch.vim).
write_project() {
  local dir=$1 sysroot first=1 f
  sysroot=$(rustc --print sysroot)
  {
    printf '{\n  "sysroot": "%s",\n' "$sysroot"
    printf '  "sysroot_src": "%s/lib/rustlib/src/rust/library",\n' "$sysroot"
    printf '  "crates": ['
    for f in "$dir"/*.rs; do
      [ -e "$f" ] || continue
      [ $first = 1 ] || printf ','
      first=0
      printf '\n    {"display_name": "%s", "root_module": "%s", "edition": "%s", "deps": [], "is_workspace_member": true, "cfg": []}' \
        "$(basename "$f" .rs)" "$f" "$EDITION"
    done
    printf '\n  ]\n}\n'
  } >"$dir/rust-project.json.new"
  if cmp -s "$dir/rust-project.json.new" "$dir/rust-project.json"; then
    rm -f "$dir/rust-project.json.new"
  else
    mv -f "$dir/rust-project.json.new" "$dir/rust-project.json"
  fi
}

# The newest .rs in a directory.
latest_rs() {
  find "$1" -maxdepth 1 -name '*.rs' -printf '%T@ %p\n' | sort -rn | head -n1 | cut -d' ' -f2-
}

cmd_check() {
  local file=${1:?usage: scratch check FILE|-}
  [ "$file" = - ] || [ -f "$file" ] || die "no such file: $file"
  local out
  out=$(mkscratch)
  # shellcheck disable=SC2064 # expand $out now
  trap "rm -rf '$out'" EXIT
  # --emit=metadata: type/borrow check and lints, no codegen.  Into a temp
  # dir, never `-o /dev/null`: rustc writes a file and renames it over the
  # output path, which as root replaces /dev/null itself.
  clippy-driver --edition "$EDITION" --crate-type bin --error-format=json \
    --emit=metadata --out-dir "$out" "${CLIPPY_FLAGS[@]}" "$file"
}

cmd_run() {
  local target=${1:?usage: scratch run FILE [ARGS...]} file out color=never status
  shift
  if [ -d "$target" ]; then
    file=$(latest_rs "$target")
    [ -n "$file" ] || die "no .rs file in $target"
  else
    file=$target
  fi
  [ -f "$file" ] || die "no such file: $file"
  file=$(realpath "$file")
  # A file in a scratch dir may be new: tell rust-analyzer about it.
  if [ -e "$(dirname "$file")/$MARKER" ]; then write_project "$(dirname "$file")"; fi
  [ -t 2 ] && color=always

  out=$(mkscratch)
  # shellcheck disable=SC2064 # expand $out now
  trap "rm -rf '$out'" EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP

  echo "── $(basename "$file") · rustc + clippy ($(date +%T))" >&2
  # clippy-driver *is* rustc with clippy's lints registered: one pass compiles,
  # lints and links the binary.
  if ! clippy-driver --edition "$EDITION" --crate-type bin --color "$color" \
    -C debuginfo=1 -o "$out/bin" "${CLIPPY_FLAGS[@]}" "$file"; then
    echo "── compile failed" >&2
    return 1
  fi
  echo "── run" >&2
  set +e
  RUST_BACKTRACE=${RUST_BACKTRACE:-1} "$out/bin" "$@"
  status=$?
  set -e
  echo "── exit $status" >&2
  return "$status"
}

cmd_watch() {
  local target=${1:-.} dir
  if [ -d "$target" ]; then dir=$target; else dir=$(dirname "$target"); fi
  [ -d "$dir" ] || die "no such directory: $dir"
  # -r: a save kills a still-running program (an infinite loop) and starts over.
  # Runs once at start, then on every save of a .rs in $dir.
  #
  # watchexec outlives a SIGHUP (a closed tmux pane), so it runs as a child
  # this shell kills on the way out, and the shell leaves when the pane goes
  # (HUP), on ^C, or once the scratch dir itself is gone.
  watchexec --restart --clear --quiet --exts rs --watch "$dir" \
    -- scratch run "$target" &
  local wpid=$!
  # shellcheck disable=SC2064 # expand $wpid now
  trap "kill $wpid 2>/dev/null || true" EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  while [ -d "$dir" ] && kill -0 "$wpid" 2>/dev/null; do sleep 1; done
}

# Globals, not locals: the EXIT trap runs after cmd_new has returned.
NEW_DIR=""
NEW_PANE=""
cleanup_new() {
  if [ -n "$NEW_DIR" ]; then rm -rf "$NEW_DIR"; fi
  # The watch pane also leaves on its own once the dir is gone.
  if [ -n "$NEW_PANE" ]; then tmux kill-pane -t "$NEW_PANE" 2>/dev/null || true; fi
}

cmd_new() {
  local dir
  trap cleanup_new EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  dir=$(mkscratch)
  NEW_DIR=$dir

  touch "$dir/$MARKER"
  printf 'fn main() {\n    \n}\n' >"$dir/main.rs"
  write_project "$dir"
  cd "$dir"

  if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null; then
    # A new pane starts from the tmux server's environment, not this shell's:
    # hand it this PATH so it sees the toolchain and `scratch`.
    NEW_PANE=$(tmux split-window -h -d -l 45% -P -F '#{pane_id}' -c "$dir" \
      -e "PATH=$PATH" "scratch watch '$dir'")
  else
    echo "scratch: not in tmux; in vim, <leader>r (or :make) compiles and runs" >&2
  fi
  "${EDITOR:-vim}" "$dir/main.rs" || true
}

case "${1:-new}" in
new) cmd_new ;;
run) shift; cmd_run "$@" ;;
watch) shift; cmd_watch "$@" ;;
check) shift; cmd_check "$@" ;;
-h | --help | help) usage ;;
*) die "unknown command: $1 (try scratch --help)" ;;
esac
