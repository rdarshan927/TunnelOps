# TunnelOps

Interactive SSH tunnel and file transfer manager built with Bash.

**Release:** v1.0.0

**License:** AGPLv3

## Project Description

TunnelOps is an interactive Bash utility for managing SSH port forwarding and remote file transfers. It supports:

- Dynamic local port forwarding (multiple `-L` mappings)
- File and directory transfer via `scp` with optional recursive copy
- Optional privileged placement on the remote host (using remote `sudo`)
- Configuration persistence and unattended auto-start (`--auto`) via a saved `config.env`

## Features

- Password or key-based SSH authentication (`sshpass` supported for password auth)
- Interactive prompts for username, server IP, auth method, and operation
- Port forwarding with multiple mappings
- File transfer with optional recursive copy and remote sudo placement
- Auto-start support using `crontab`/`cronie` (interactive install prompt available)
- Logs and configuration stored in user directories following XDG conventions

## Requirements

- Bash (recommended v4+)
- OpenSSH client tools: `ssh`, `scp`
- Optional: `sshpass` (for password-based authentication)
- Optional: `cronie` (for cron-based auto-start)

## Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/rdarshan927/tunnelops.git
cd tunnelops
chmod +x tunnel.sh
```

### AUR (Arch Linux)

Install from the Arch User Repository (example using `yay`):

```bash
yay -S tunnelops
```

Optional dependencies (install as needed):

- `sshpass` — required only for password-based SSH authentication
- `cronie` — optional, required for cron auto-start support

## Usage

Run interactively (installed or local):

```bash
# If installed from AUR
tunnelops

# If running from repository
./tunnel.sh
```

Example unattended mode (auto):

```bash
./tunnel.sh --auto
```

Notes:

- When installed from AUR the command `tunnelops` runs the packaged script.
- `--auto` loads `config.env` from the user's configuration directory and starts the saved tunnels without interactive prompts.

### Interactive Prompts

The script will prompt for the following information when run interactively:

- SSH username
- Remote server IP address (IPv4)
- Authentication method:
  - Password (requires `sshpass`), or
  - SSH private key file path
- Operation type:
  1) Port Forwarding — enter the number of mappings, then for each mapping enter a local port and remote port
  2) File Transfer — provide local path, remote destination, choose recursive if copying directories, and indicate if remote sudo is required

### Port Forwarding

- Builds and runs an `ssh -N -f` command with one or more `-L` rules
- Runs the tunnel in the background and logs output to the user log file

### File Transfer

- Uses `scp` for file and directory transfers
- For password auth the script uses `sshpass` if available
- If remote sudo is required, the script uploads to a temporary path (e.g., `/tmp/...`) and attempts a `sudo mv` on the remote host via `ssh`

## Configuration & Logs

- Configuration (saved by the script) is stored at:

```
~/.config/tunnelops/config.env
```

- Logs are stored at:

```
~/.local/share/tunnelops/logs/tunnel.log
```

These paths respect the XDG environment variables `XDG_CONFIG_HOME` and `XDG_DATA_HOME` when set.

## Cron / Auto-start

- The script can add an `@reboot` cron job to start saved tunnels at user login/reboot.
- If `crontab`/`cron` is not found, the script offers to detect the package manager and install `cron` or `cronie` interactively (requires `sudo`).

## Links and References

- GitHub repository: https://github.com/rdarshan927/tunnelops
- AUR package page: https://aur.archlinux.org/packages/tunnelops

## Security Notes

- Password-based authentication stores credentials in `config.env` only if you choose to save configuration; files are written with restrictive permissions.
- For unattended use, prefer SSH key authentication and avoid saving plaintext passwords where possible.
- Protect private keys with `chmod 600`.

## Contributing

Contributions, issues, and suggestions are welcome. When submitting changes, follow secure coding practices and avoid embedding sensitive credentials in source.

## License

This project is distributed under the GNU Affero General Public License v3.0 (AGPLv3). See the `LICENSE` file for full terms.