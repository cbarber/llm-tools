# macOS sandbox-exec Research Notes

Findings from iterative CI probing on macOS 15 ARM64 (macos-15-arm64, Feb 2026 image).

## How `(subpath ...)` works

`(subpath "/foo")` is a **string prefix match** on the literal path, not a filesystem traversal. Symlinks are not resolved. This means:

- `(subpath "/Volumes")` does NOT grant access to `/Volumes/Macintosh HD/Users/...` even though `/Volumes/Macintosh HD` symlinks to `/`
- `(subpath "/System")` does NOT grant access to `$HOME` via `/System/Volumes/Data/Users/runner` through symlink resolution
- Non-existent paths in `(subpath ...)` are safe — no SIGABRT, the rule simply never matches

## The root inode requirement

Any profile that omits a read rule covering `/` will SIGABRT at launch (exit 134), even if every visible directory under `/` is listed explicitly. The kernel reads the root inode as part of process setup before the process gets to run.

Two forms satisfy this:

- `(literal "/")` — allows exactly the root inode, nothing else
- `(subpath "/")` — allows all paths (too broad)
- `(regex #"^/")` — also works; equivalent coverage to `(subpath "/")` without the special-casing

`(literal "/")` is the right choice: it satisfies the prereq with minimal scope.

## Why explicit directory lists failed

Listing every visible root directory (`/System`, `/usr`, `/bin`, ...) still SIGABRTs without `(literal "/")`. The missing piece is the root inode itself, which no directory entry represents.

## `file-read*` operation breakdown

`file-read*` expands to exactly three operations — no hidden ones:

- `file-read-data`
- `file-read-metadata`
- `file-map-executable`

`file-map-executable` is **not** required to launch a process. Dropping it from an allowlist still works.

## `/Volumes` should be excluded

`/Volumes/Macintosh HD` is a symlink to `/`. While string-prefix matching means it doesn't actually grant broader access today, it's a theoretical risk if the kernel's evaluation ever changes. It is not required for process launch.

## `/private` is required

macOS `TMPDIR` is `/var/folders/.../T/`, which is a symlink to `/private/var/folders/.../T/`. The canonical path (used in sandbox params) falls under `/private`. Without `(subpath "/private")`, temp file operations fail.

`$HOME` on macOS is `/Users/<user>`, which does not fall under `/private`. The two are unrelated.

## `/home` is not `$HOME`

`/home` is a symlink to `/System/Volumes/Data/home` — the auto-mount point for network home directories. Standard user home directories are under `/Users`. `/home` does not need to be in the allowlist.

## `sandbox-exec` limitations vs bubblewrap

- Cannot remap mounts — no equivalent to `--bind src dst`
- `(trace ...)` directive requires `sandboxd`, which is unavailable in GitHub Actions CI
- SIGABRT from a denied operation produces no stderr output; the only signal is exit code 134
- Profile parameters (`-D`) must reference existing paths for `(subpath (param "..."))` — missing paths cause SIGABRT
