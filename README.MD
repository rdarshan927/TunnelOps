TunnelOps

TunnelOps is an interactive Bash utility for managing SSH port forwarding and remote file transfers. It provides an easy CLI to configure SSH connections, create background tunnels, copy files or directories to remote hosts, and optionally enable auto-start at system boot.

## Features

- SSH authentication via password (using `sshpass`) or private key
- Interactive configuration for connection details and operations
- Dynamic port forwarding supporting multiple `-L` mappings
- File transfer using `scp` with optional recursive copy
- Optional upload with remote `sudo` move when elevated permissions are required
- Optional startup automation using `crontab` with `@reboot`
- Automatic detection and optional installation of cron (interactive)
- Configuration persistence to `config.env` for `--auto` mode
- Operation and error logging to `logs/tunnel.log`

## Requirements

- Bash (recommended v4+)
- OpenSSH client tools: `ssh`, `scp`
- `sshpass` (only required for password-based authentication)
- `crontab`/`cron` (optional, only for the auto-start feature)

Note: The script checks for required tools and prompts when something is missing.

## Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/rdarshan927/TunnelOps.git
cd TunnelOps
chmod +x tunnel.sh
```

## Usage

Run the script interactively:

```bash
./tunnel.sh
```

You will be prompted for:

- SSH username and remote server IP
- Authentication method: password or SSH key
- Operation: Port Forwarding or File Transfer

### Port Forwarding

If you choose Port Forwarding you will be asked how many ports to forward and the local/remote port pairs. The script will build an `ssh -N -f` command with all `-L` rules and run it in the background. You can optionally save the configuration and enable automatic start at boot.

Example:

```text
Local 5678 -> Remote 5678
Local 8080 -> Remote 80
```

### File Transfer

If you choose File Transfer you will be asked for:

- Local file or directory path
- Remote destination path
- Whether to use recursive copy (for directories)
- Whether the remote destination requires elevated (sudo) permissions

Behavior:

- Uses `scp` for transfers; `sshpass` is used if password authentication is selected
- If remote sudo is required, the file is uploaded to a temporary path (e.g., `/tmp/...`) and the script attempts a `sudo mv` via `ssh` to place the file into the privileged destination. If that fails, the temporary location is reported.

Example commands performed by the script (internal):

- File copy: `scp file user@host:/path`
- Directory copy: `scp -r dir user@host:/path`

## Auto Mode

You can save a port-forwarding configuration to `config.env` and enable an `@reboot` cron job. Then the script can be started automatically on boot with:

```bash
./tunnel.sh --auto
```

The `--auto` mode currently supports starting saved port-forwarding tunnels from `config.env`.

## Cron dependency and installation

When enabling auto-start the script checks for `crontab`. If it is not present, you'll be prompted to install it. The script can detect common package managers (`apt`, `yum`, `pacman`) and will attempt to install the appropriate package (`cron` or `cronie`) if you consent. If installation is skipped or fails, auto-start setup is aborted safely.

## Logs

Operations and errors are logged to `logs/tunnel.log`. Example entries include INFO, SUCCESS, WARN, and ERROR level lines.

## Files

- `tunnel.sh` — main script
- `config.env` — saved configuration (created when enabling auto-start)
- `logs/tunnel.log` — operation and error log

## Security Notes

- Password-based authentication uses `sshpass` and may expose credentials in memory. Prefer SSH keys.
- Protect private keys with proper permissions: `chmod 600 /path/to/id_rsa`.
- Be cautious when enabling auto-start with stored passwords; consider using key-based auth instead.

## License

This project is licensed under the GNU Affero General Public License v3.0. See the `LICENSE` file for full terms.

## Contributing

Contributions and issues are welcome. Please follow good security practices when suggesting changes involving credentials.

## Quick Start Examples

Start an interactive session:

```bash
./tunnel.sh
```

Start from saved config (auto mode):

```bash
./tunnel.sh --auto
```

---
Updated README to be clearer and better structured for quick reference.
You are free to use, modify, and distribute this software under the terms of the license. Any modifications made and deployed over a network must also make the source code available under the same license.

See the LICENSE file for full details.