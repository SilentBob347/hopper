# ɹǝddoH (Hopper)

<p align="center">
  <img src="screenshots/app-icon.png" width="128" alt="ɹǝddoH app icon">
</p>

iOS VPN client and Linux server stack for a **multi-hop SSH overlay**: traffic is tunneled as raw IP packets over SSH, routed through a chain of nodes, and NAT’d at the exit. One app, one server daemon (`hopperd`), no legacy relays.

## Screenshots

### iPhone

<p align="center">
  <img src="screenshots/iphone/01-home.png" width="200" alt="Home — chain, connect, and route">
  <img src="screenshots/iphone/02-chain.png" width="200" alt="Chain detail — entry to exit hops">
  <img src="screenshots/iphone/03-servers.png" width="200" alt="Server library">
  <img src="screenshots/iphone/04-provisioning.png" width="200" alt="Provisioning chain on connect">
</p>

### iPad

<p align="center">
  <img src="screenshots/ipad/01-home.png" width="280" alt="Home — connected VPN">
  <img src="screenshots/ipad/02-servers.png" width="280" alt="Server library">
  <img src="screenshots/ipad/03-chain.png" width="280" alt="Chain detail">
  <img src="screenshots/ipad/04-chains.png" width="280" alt="Chains list">
</p>

---

## How it works

```mermaid
flowchart LR
  subgraph ios [iOS]
    App[Hopper app]
    Ext[Packet tunnel extension]
    App -->|provision chain| Ext
    Ext -->|SSH + iptunnel| Entry
  end

  subgraph chain [Server chain entry to exit]
    Entry[hopperd entry]
    Relay[hopperd relay]
    Exit[hopperd exit]
    Entry -->|SSH pipe| Relay
    Relay -->|SSH pipe| Exit
  end

  Ext --> Entry
  Exit -->|TUN + NAT| Internet[(Internet)]
```

| Layer        | Role                                                                                             |
| ------------ | ------------------------------------------------------------------------------------------------ |
| **iOS**      | L3 VPN (`NEPacketTunnelProvider`). All IPv4 default traffic → overlay client `10.64.0.2`.        |
| **iptunnel** | Framed IP over a byte stream (SSH `direct-tcpip` to `127.0.0.1:7400`).                           |
| **hopperd**  | Userspace routing between ingress (client), `next` (downstream hop), and TUN (internet on exit). |
| **SSH**      | App → entry hop; each hop → next hop via local `~/.hopper/id_ed25519`.                           |

### Two-phase connect

1. **Provision (exit → entry)** — The app SSH-execs `start_server.sh` on each hop, last to first: trust upstream keys, write `hopper.json`, start `hopperd`.
2. **VPN (entry only)** — Extension SSH-connects to the **first** hop in the chain, opens iptunnel to local `hopperd`, and carries packets.

Chain order in the app: **first = entry**, **last = exit**.

### Overlay (`10.64.0.0/24`)

| Address              | Use                              |
| -------------------- | -------------------------------- |
| `10.64.0.2`          | iOS client                       |
| `10.64.0.10` + index | Hop *i* in chain (entry = `.10`) |
| `0.0.0.0/0`          | Relay → `next`; exit → TUN + NAT |

---

## Requirements

### Server (each hop)

- Linux with TUN (`/dev/net/tun`)
- `python3`, `ip`, `iptables` (exit NAT)
- Root or `cap_net_admin` on `hopperd` (set by `configure_server.sh` when run as root)
- SSH access for deploy and for inter-hop / client connections

### iOS

- Xcode 16+, iOS 17+
- Apple Developer account with **Network Extension** (Packet Tunnel) entitlement
- App Group: `group.com.aengix.hopper`

### Dev machine

- Go 1.22+ (build server binaries)
- SSH key to target servers (`~/.ssh/id_rsa` by default)

---

## Quick start

### 1. Deploy a hop

From your Mac:

```bash
cd server
./deploy.sh YOUR_SERVER_IP
```

This will:

- Build `dist/hopperd-linux-{amd64,arm64}`
- Upload bundle to `~/hopper` on the server
- Run `configure_server.sh --json-only` and open a **local QR page** in the browser (deleted after 5 seconds)

Options (same as `remove.sh`):

| Flag         | Default         | Meaning              |
| ------------ | --------------- | -------------------- |
| `-u`         | `root`          | SSH user             |
| `-p`         | `22`            | SSH port             |
| `-i`         | `~/.ssh/id_rsa` | SSH private key      |
| `-P`         | `~/hopper`      | Remote install path  |
| `-y`         | —               | Skip confirmation    |
| `--no-build` | —               | Skip `build_dist.sh` |

Environment: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PORT`, `DEPLOY_KEY`, `DEPLOY_PATH`.

### 2. Add hops in the app

1. Open **ɹǝddoH** → **Configure chains** → **Server library** → **Scan QR** (once per machine).
2. **New chain** → name it → **Add server…** in order **entry → exit**.
3. Swipe **Use** or pick the chain on the home screen → **Connect**.

### 3. Remove a hop

```bash
./remove.sh YOUR_SERVER_IP
```

Stops `hopperd`, removes `~/hopper`, `~/.hopper`, TUN `hopper0`, hopper NAT rules, and hopper lines in `authorized_keys`.

---

## Server reference

### Layout on the machine

```
~/hopper/
  configure_server.sh   # one-time / re-run: keys + JSON profile
  start_server.sh       # app-invoked: config + start hopperd
  hopper_common.sh
  dist/
    hopperd-linux-amd64
    hopperd-linux-arm64

~/.hopper/
  id_ed25519            # inter-hop + hopperd SSH identity
  hopper.json           # runtime config
  hopper.log
```

### Scripts

| Script                | Who runs it         | Purpose                                                                          |
| --------------------- | ------------------- | -------------------------------------------------------------------------------- |
| `configure_server.sh` | Admin / `deploy.sh` | Generate host keypair, `authorized_keys`, optional `setcap`, emit QR JSON        |
| `start_server.sh`     | iOS via SSH exec    | `--stop-only`, `--trust-pubkey`, write config, start `hopperd`, print ready JSON |
| `deploy.sh`           | Developer           | Build, upload, configure, browser QR                                             |
| `remove.sh`           | Developer           | Uninstall                                                                        |
| `build_dist.sh`       | Developer           | Cross-compile `hopperd`                                                          |

#### `configure_server.sh`

```bash
./configure_server.sh                    # interactive on server
./configure_server.sh --json-only --host 1.2.3.4 --port 22
```

#### `start_server.sh` (provision)

```bash
./start_server.sh --role exit --addr 10.64.0.12 --index 2 \
  --overlay 10.64.0.0/24 --client-addr 10.64.0.2

./start_server.sh --role relay --addr 10.64.0.11 --index 1 \
  --client-addr 10.64.0.2 \
  --next-host hop2.example.com --next-port 22 --next-user root
```

Stdout: one JSON line, e.g. `{"ready":true,"mode":"exit","addr":"10.64.0.12",...}`.

### `hopperd`

```bash
~/.hopper/hopper.json    # default config path
./dist/hopperd-linux-amd64 -verbose --config ~/.hopper/hopper.json --ready-file ~/.hopper/hopper-ready
```

Listens on `127.0.0.1:7400` only (reached via SSH forwarding).

Example config: [`server/hopper.example.json`](server/hopper.example.json).

### Build server only

```bash
cd server
./build_dist.sh
```

Binaries land in `server/dist/` (gitignored).

---

## iOS app reference

### Screens

| Screen               | Purpose                                         |
| -------------------- | ----------------------------------------------- |
| **Home**             | Select chain, connect/disconnect, route preview |
| **Configure chains** | Create/delete chains, open server library       |
| **Chain detail**     | Name, reorder hops, add/remove servers          |
| **Server library**   | Scan QR, delete saved servers                   |

Profiles persist in the App Group (`hopper-profiles.json`).

### QR payload (v2)

```json
{
  "v": 2,
  "name": "hostname",
  "host": "203.0.113.10",
  "port": "22",
  "user": "root",
  "private_key": "-----BEGIN OPENSSH PRIVATE KEY-----\n...",
  "host_key": ["ssh-ed25519 AAAA..."],
  "install_dir": "/root/hopper"
}
```

The app stores servers in a library; chains reference server IDs in order.

### Build & run

```bash
cd app
open Hopper.xcodeproj
```

- Target **Hopper** (app) + **HopperExtension** (packet tunnel)
- Citadel (vendored SSH) is linked to both app (provision) and extension (data plane)
- Signing: set your `DEVELOPMENT_TEAM`, enable Network Extension + App Groups

Regenerate Xcode project (optional):

```bash
ruby app/Scripts/generate_xcodeproj.rb
```

### Project layout

```
app/
  Hopper/              SwiftUI app, VPNController, ChainProvisioner
  HopperExtension/     PacketTunnelProvider
  TunnelCore/          SSHHopConnector, IPTunnelEngine, HopSSH
  Shared/              Models, HopConstants, ProfileStore
  Vendor/Citadel/      SSH client library
server/
  cmd/hopperd/         Daemon entrypoint
  internal/hopper/     Config, session routing, NAT, SSH next-hop
  internal/iptunnel/   Frame protocol + Linux TUN
```

---

## Troubleshooting

| Symptom                   | Things to check                                                                  |
| ------------------------- | -------------------------------------------------------------------------------- |
| VPN connects, no internet | Exit NAT: `iptables -t nat -L`; `hopper.log` on exit; re-connect to re-provision |
| Chain provision fails     | SSH from app to each hop; `start_server.sh` on server; keys in `authorized_keys` |
| `hopperd` won’t start     | Root/`setcap cap_net_admin`; read `~/.hopper/hopper.log`                         |
| Extension errors          | App Group + embedded extension; delete app and reinstall VPN profile             |

**Logs**

- Server: `~/.hopper/hopper.log`
- iOS: Xcode → Window → Devices → open console for device, filter `Hopper`

**Manual stop on server**

```bash
cd ~/hopper && ./start_server.sh --stop-only
```

---

## Security notes

- QR and deploy HTML contain **private keys** — treat as secrets; deploy deletes local HTML after 5s.
- Each hop has its own `~/.hopper/id_ed25519`; provision adds upstream pubkeys to downstream `authorized_keys`.
- `hopperd` binds to loopback; only SSH-forwarded clients reach iptunnel.
- Review `authorized_keys` after `remove.sh` if you added keys manually.

---

## License

See repository for license terms. Citadel is vendored under its own license in `app/Vendor/Citadel/`.
