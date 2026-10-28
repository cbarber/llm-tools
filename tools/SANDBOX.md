# Agent Sandboxing

Agents run in a deny-by-default sandbox via [fence](https://github.com/fencesandbox/fence), which wraps bubblewrap on Linux and Seatbelt on macOS behind one JSON config. The security model is the same on both platforms.

## Security Model

| Category | Access |
| --- | --- |
| Project directory | read-write |
| Temp workspace (`$AGENT_WORK_DIR`) | read-write |
| Agent config/cache dirs (`~/.config/opencode`, etc.) | read-write |
| Git identity files (`~/.gitconfig`, `~/.ssh/known_hosts`) | read-only |
| OS directories (`/usr`, `/bin`, `/lib`, `/nix`, etc.) | read-only |
| Nix daemon socket | untrusted client |
| `~/.ssh` (keys), `~/.gnupg` | **denied** |
| Host IPC sockets that act outside the sandbox | **masked** (see below) |
| Rest of home directory | **denied** |
| Other project directories | **denied** |

## Configuration

`agent-sandbox.sh` builds a per-session fence config with `defaultDenyRead: true` — only paths in `allowRead`/`allowWrite` are visible; everything else is absent. Path lists are built by `setup-sandbox-paths.sh` from the project directory, git dirs, agent config/cache dirs, and `$PATH`.

Key environment variables:

- `AGENT_SANDBOX_BIND_HOME=true` — allow writes to the entire `$HOME` (breaks isolation)
- `SANDBOX_EXTRA_RO=path1:path2` — additional read-only paths
- `SANDBOX_EXTRA_RW=path1:path2` — additional read-write paths
- `SANDBOX_LOCAL_OUTBOUND_PORTS=5432:6379` — host loopback ports available inside Fence on Linux
- `FENCE_PATH` — path to the `fence` binary (set by the nix shellHook)

## Unix Sockets

On Linux fence has no Unix socket policy (`allowUnixSockets` is macOS-only) and binds `/run` read-only, so any socket the user can connect to on the host is reachable unless its path is hidden. `agent-sandbox.sh` adds each socket that acts outside the sandbox to `denyRead`; fence then binds `/dev/null` over a socket (a connect fails with `ECONNREFUSED` because the path is no longer a socket) or an empty tmpfs over a directory. Paths that do not exist at launch are skipped. `$RUNTIME` below is `$XDG_RUNTIME_DIR`, else `/run/user/$(id -u)`.

A socket is masked when it runs commands, acts with the user's or root's authority, or reaches input, audio or screen devices. It is kept when its service checks the caller's credentials itself or only answers queries and accepts logs.

Audit of the sockets reachable from inside the sandbox on a NixOS/Hyprland host (TASK-104, connect-only probes):

| Socket | Decision | Reason |
| --- | --- | --- |
| `$RUNTIME/bus`, and the path in `DBUS_SESSION_BUS_ADDRESS` | masked | Session bus: `systemd-run --user` (`StartTransientUnit`) and other services run commands as the user |
| `$RUNTIME/systemd/private`, `$RUNTIME/systemd/io.systemd.Manager` | masked | User systemd manager: starts units outside the sandbox |
| `$RUNTIME/systemd/notify`, `$RUNTIME/systemd/report/io.systemd.Manager` | kept | Notifications from non-unit processes are ignored; report is read-only metrics |
| `$RUNTIME/podman/podman.sock`, `$RUNTIME/docker.sock` | masked | Rootless container API: a container can mount the user's home |
| `/run/podman/podman.sock`, `/run/docker.sock` | masked | Rootful container API: root on the host (podman's was connectable through a supplementary group) |
| `SSH_AUTH_SOCK`, `$RUNTIME/gcr/ssh`, `$RUNTIME/gcr/.ssh` | masked | SSH agent signs as the user; the sandbox has no SSH keys by design |
| `$RUNTIME/gnupg` (gpg-agent `S.gpg-agent*`) | masked | Signs and decrypts as the user; `~/.gnupg` is already denied |
| `$RUNTIME/keyring` (`control`, `pkcs11`) | masked | GNOME Keyring holds the user's secrets and keys |
| `$RUNTIME/hypr`, `SWAYSOCK`, `NIRI_SOCKET` | masked | Compositor IPC runs commands (`hyprctl dispatch exec`, `swaymsg exec`, `niri msg action spawn`) |
| `$RUNTIME/$WAYLAND_DISPLAY` | masked | Wayland clients can use virtual keyboard and screencopy protocols on wlroots-style compositors |
| `/tmp/.X11-unix` (`X0`) | masked | X11 clients can inject keystrokes (XTEST) and read other windows |
| `${TMUX_TMPDIR:-/tmp}/tmux-$UID` | masked | `tmux send-keys` types into panes outside the sandbox |
| `$RUNTIME/pipewire-0`, `$RUNTIME/pipewire-0-manager`, `$RUNTIME/pulse/native` | masked | Microphone capture and audio graph control |
| `$RUNTIME/voxtype/audio.sock` | masked | Voice typing daemon types text into the focused window |
| `$RUNTIME/wayland-1-awww-daemon.sock` | kept | Wallpaper daemon; sets the wallpaper only |
| `$RUNTIME/discord-ipc-*` | kept | Discord RPC; anything beyond presence needs the user's approval in Discord |
| `$RUNTIME/speech-dispatcher/speechd.sock` | kept | Speech output only |
| `/run/dbus/system_bus_socket` | masked | Sandbox processes are in the user's active session, so polkit `allow_active` actions (power off, mounts, network changes) are granted |
| `/run/tailscale/tailscaled.sock` | masked | Tailscale local API: status of the tailnet, and as an operator user, `serve`/`funnel` of local ports |
| `/run/clamav/clamd.ctl` | masked | Accepts `SHUTDOWN` from any local user |
| `/nix/var/nix/daemon-socket/socket` | kept | Nix daemon; the user is an untrusted client (TASK-91) |
| `/run/nscd/socket`, `/run/systemd/userdb/*`, `/run/systemd/resolve/*` | kept | Name, user and DNS lookups the sandbox needs |
| `/run/systemd/journal/*` | kept | Logging only |
| `/run/systemd/io.systemd.{Credentials,Hostname,Login,ManagedOOM,Manager}`, `/run/systemd/oom/*`, `/run/systemd/report/*`, `/run/systemd/notify` | kept | System varlink: privileged methods check the caller's credentials; the rest are read-only |
| `/run/systemd/private`, `/run/udev/*`, `/run/systemd/coredump`, `/run/systemd/io.systemd.{BootControl,JournalAccess}`, `/run/greetd-*.sock` | kept | Root-only: connect fails with `EACCES` |
| `/run/polkit/agent-helper.socket` | kept | Authentication needs a cookie issued to a registered agent |
| `/run/ssh-unix-local/socket` | kept | Local sshd; needs keys, which the sandbox does not have |
| `/run/cups/cups.sock` | kept | Printing; administration requires authentication |
| `/run/acpid.socket` | kept | ACPI event stream, read-only |
| This session's `fence-{http,socks}-*.sock` | kept | fence's own proxy bridges, which carry the sandbox's network traffic |
| Other sessions' `/tmp/nix-shell.*/fence-{http,socks}-*.sock` | kept (gap) | Reachable through the shared host `/tmp`; they route traffic under that session's egress policy and upstream proxy, bypassing this session's. Masking by path cannot keep up with sessions started later |
| `/tmp/scoped_dir*/SingletonSocket` (Chromium) | kept (gap) | Reachable through the shared host `/tmp`; asks the running browser to open URLs. Its directory name is random |
| `~/.config/herdr/herdr.sock` and other sockets under `$HOME` | denied | Home is not readable (`defaultDenyRead`), though `HERDR_SOCKET_PATH` still names it |

Gaps:

- **Unlisted and later sockets.** Masks are per path and resolved at launch. A socket created after launch, or one not in the list (for example Neovim's `$RUNTIME/nvim.*.0` server, kitty or WezTerm remote control, Zellij, Emacs server), stays reachable. Several of these run commands.
- **Recreated sockets.** A masked socket file is covered by a `/dev/null` bind in the sandbox's mount namespace. When the host unlinks that path (a service restart, socket reactivation, a new `ssh-agent`), Linux since 3.18 detaches mounts on it in every namespace, so the socket recreated at the same path is likely reachable from a running sandbox. This affects the single-file masks (`$RUNTIME/bus`, `$RUNTIME/systemd/private`, `$RUNTIME/systemd/io.systemd.Manager`, `$RUNTIME/gcr/ssh`, `SSH_AUTH_SOCK`); masked directories stay masked while the directory exists. Not yet verified.
- **Shared `/tmp` and `/run`.** `agent-sandbox.sh` binds the host `/tmp` read-write, and fence binds all of `/run` unless `strictDenyRead` is set. Both expose sockets of other sessions and programs. The structural fixes, `strictDenyRead` with an explicit allowlist of the `/run` paths the sandbox needs, and a private `/tmp` with a per-session work directory, change what every session can see and need a launch outside the sandbox to verify. They are open decisions.
- **Environment.** `DBUS_SESSION_BUS_ADDRESS`, `SSH_AUTH_SOCK`, `DISPLAY`, `WAYLAND_DISPLAY` and `HERDR_SOCKET_PATH` still reach the sandbox. They name masked or denied paths, so clients fail to connect rather than reach the host.
- **Abstract sockets.** Abstract Unix sockets (`@name` in `/proc/net/unix`) have no path to mask and belong to a network namespace. When a credential proxy is configured, fence runs with `--unshare-net` (where the host allows it) and the host's abstract sockets are unreachable. With `allowedDomains: ["*"]` and no proxy, fence skips `--unshare-net`, so every host abstract socket (for example X11's `@/tmp/.X11-unix/X0`) is reachable.
- **macOS.** Seatbelt denies Unix socket connects unless `allowUnixSockets` lists them, and the config lists none. That holds only in proxy mode: with `allowedDomains: ["*"]` fence emits `(allow network*)`, which allows every Unix socket, including `SSH_AUTH_SOCK`. The Linux paths above do not exist on macOS.

`tools/test-agent-sandbox.bats` checks that the deny list carries these paths, and that a masked socket inside the sandbox is `/dev/null` and refuses connects while an unmasked sibling connects. The launch tests need a run outside the sandbox.

## Disabling the Sandbox

```bash
AGENT_SANDBOX=false nix develop .#claude-code
```
