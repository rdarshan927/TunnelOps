#!/usr/bin/env bash

# tunnel.sh
# Interactive SSH tunnel manager + SCP transfer utility with optional auto-start on boot.

set -u

# Define user-level configuration and logging directories following XDG Base Directory spec
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tunnelops"
LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tunnelops/logs"
CONFIG_FILE="$CONFIG_DIR/config.env"
LOG_FILE="$LOG_DIR/tunnel.log"
CRON_MARKER="# tunnel_manager_auto"

# -----------------------------
# Logging helpers
# -----------------------------
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

info() { log "INFO" "$*"; }
success() { log "SUCCESS" "$*"; }
warn() { log "WARN" "$*"; }
error() { log "ERROR" "$*" >&2; }

# -----------------------------
# Utility checks/validators
# -----------------------------
ensure_directories() {
    mkdir -p "$CONFIG_DIR" || {
        error "Failed to create config directory: $CONFIG_DIR"
        return 1
    }
    mkdir -p "$LOG_DIR" || {
        error "Failed to create log directory: $LOG_DIR"
        return 1
    }
    touch "$LOG_FILE" || {
        error "Failed to create log file: $LOG_FILE"
        return 1
    }
}

require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        error "Required tool '$tool' is not installed or not in PATH."
        return 1
    fi
}

is_valid_ip() {
    local ip="$1"
    local IFS='.'
    local -a octets

    # Basic IPv4 pattern check
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        ((octet >= 0 && octet <= 255)) || return 1
    done

    return 0
}

is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    ((port >= 1 && port <= 65535)) || return 1
    return 0
}

prompt_non_empty() {
    local prompt_text="$1"
    local value

    while true; do
        read -r -p "$prompt_text" value
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
        error "Input cannot be empty."
    done
}

prompt_yes_no() {
    local prompt_text="$1"
    local answer

    while true; do
        read -r -p "$prompt_text" answer
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) error "Please answer y or n." ;;
        esac
    done
}

get_script_path() {
    if command -v realpath >/dev/null 2>&1; then
        realpath "$0"
    elif command -v readlink >/dev/null 2>&1; then
        readlink -f "$0"
    else
        echo "$SCRIPT_DIR/tunnel.sh"
    fi
}

# -----------------------------
# Welcome banner
# -----------------------------
show_welcome() {
        cat <<'BANNER'

=========================================
    TunnelOps — SSH Tunnel & File Manager
    Interactive mode. Type Ctrl+C to cancel.
    For unattended startup use: ./tunnel.sh --auto
=========================================

BANNER

        info "Starting TunnelOps interactive session"
}

# -----------------------------
# Tunnel command assembly/start
# -----------------------------
build_forwarding_rules() {
    local -n _out_array="$1"
    local i

    _out_array=()
    for ((i = 0; i < PORT_COUNT; i++)); do
        _out_array+=("-L" "${LOCAL_PORTS[$i]}:127.0.0.1:${REMOTE_PORTS[$i]}")
    done
}

forwarded_ports_summary() {
    local i
    local summary=""

    for ((i = 0; i < PORT_COUNT; i++)); do
        summary+="${LOCAL_PORTS[$i]}->${REMOTE_PORTS[$i]}"
        if ((i < PORT_COUNT - 1)); then
            summary+=", "
        fi
    done

    echo "$summary"
}

start_tunnel() {
    local -a base_cmd
    local -a full_cmd
    local -a forwarding

    build_forwarding_rules forwarding

    base_cmd=(ssh -N -f -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new)

    if [[ "$AUTH_METHOD" == "key" ]]; then
        if [[ ! -f "$KEY_PATH" ]]; then
            error "SSH key file not found: $KEY_PATH"
            return 1
        fi
        if [[ ! -r "$KEY_PATH" ]]; then
            error "SSH key file is not readable: $KEY_PATH"
            return 1
        fi
        full_cmd=("${base_cmd[@]}" -i "$KEY_PATH" "${forwarding[@]}" "${SSH_USER}@${SERVER_IP}")
    else
        require_tool sshpass || return 1
        full_cmd=(sshpass -p "$PASSWORD" "${base_cmd[@]}" "${forwarding[@]}" "${SSH_USER}@${SERVER_IP}")
    fi

    info "Starting SSH tunnel to $SSH_USER@$SERVER_IP"
    if "${full_cmd[@]}" >> "$LOG_FILE" 2>&1; then
        success "Tunnel started successfully. Forwarded ports: $(forwarded_ports_summary)"
        return 0
    else
        error "Failed to start SSH tunnel. Check $LOG_FILE for details."
        return 1
    fi
}

# -----------------------------
# File transfer helpers
# -----------------------------
execute_ssh_command() {
    local remote_cmd="$1"
    local -a cmd

    if [[ "$AUTH_METHOD" == "key" ]]; then
        cmd=(ssh -o StrictHostKeyChecking=accept-new -i "$KEY_PATH" "${SSH_USER}@${SERVER_IP}" "$remote_cmd")
    else
        require_tool sshpass || return 1
        cmd=(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${SERVER_IP}" "$remote_cmd")
    fi

    "${cmd[@]}" >> "$LOG_FILE" 2>&1
}

build_scp_command() {
    local -n _out_cmd="$1"

    _out_cmd=(scp -o StrictHostKeyChecking=accept-new)

    if [[ "$AUTH_METHOD" == "key" ]]; then
        _out_cmd+=(-i "$KEY_PATH")
    else
        require_tool sshpass || return 1
        _out_cmd=(sshpass -p "$PASSWORD" "${_out_cmd[@]}")
    fi

    if [[ "$USE_RECURSIVE" == "yes" ]]; then
        _out_cmd+=(-r)
    fi

    return 0
}

copy_files() {
    local source_path="$LOCAL_SOURCE_PATH"
    local remote_path="$REMOTE_DEST_PATH"
    local remote_temp_path
    local remote_target
    local remote_path_escaped
    local temp_path_escaped
    local remote_move_cmd
    local -a scp_cmd

    require_tool scp || return 1

    if [[ ! -e "$source_path" ]]; then
        error "Local source path does not exist: $source_path"
        return 1
    fi

    if [[ -z "$remote_path" ]]; then
        error "Remote destination path cannot be empty."
        return 1
    fi

    if [[ -d "$source_path" && "$USE_RECURSIVE" != "yes" ]]; then
        error "Source is a directory. Recursive copy is required (-r)."
        return 1
    fi

    build_scp_command scp_cmd || return 1

    if [[ "$NEED_REMOTE_SUDO" == "yes" ]]; then
        remote_temp_path="/tmp/tunnel_upload_$(date +%s)_$(basename "$source_path")"
        temp_path_escaped="${remote_temp_path// /\\ }"
        remote_target="${SSH_USER}@${SERVER_IP}:${temp_path_escaped}"

        info "Uploading to temporary remote path: $remote_temp_path"
        if ! "${scp_cmd[@]}" "$source_path" "$remote_target" >> "$LOG_FILE" 2>&1; then
            error "Upload to temporary remote path failed."
            return 1
        fi

        remote_move_cmd="sudo mkdir -p \"$(dirname "$remote_path")\" && sudo mv \"$remote_temp_path\" \"$remote_path\""
        info "Attempting privileged move on remote host using sudo."
        if execute_ssh_command "$remote_move_cmd"; then
            success "File transfer completed with remote sudo move to: $remote_path"
            return 0
        fi

        warn "Remote sudo move failed. File is currently at: $remote_temp_path"
        warn "You may move it manually with: sudo mv '$remote_temp_path' '$remote_path'"
        return 1
    fi

    remote_path_escaped="${remote_path// /\\ }"
    remote_target="${SSH_USER}@${SERVER_IP}:${remote_path_escaped}"

    info "Starting file transfer to $SSH_USER@$SERVER_IP:$remote_path"
    if "${scp_cmd[@]}" "$source_path" "$remote_target" >> "$LOG_FILE" 2>&1; then
        success "File transfer completed successfully to: $remote_path"
        return 0
    else
        error "File transfer failed. Check $LOG_FILE for details."
        return 1
    fi
}

# -----------------------------
# Config persistence/load
# -----------------------------
save_config() {
    local old_umask
    old_umask="$(umask)"
    umask 077

    {
        echo "# Auto-generated by tunnel.sh"
        printf 'SSH_USER=%q\n' "$SSH_USER"
        printf 'SERVER_IP=%q\n' "$SERVER_IP"
        printf 'AUTH_METHOD=%q\n' "$AUTH_METHOD"
        printf 'OPERATION=%q\n' "port_forwarding"
        printf 'KEY_PATH=%q\n' "${KEY_PATH:-}"
        printf 'PASSWORD=%q\n' "${PASSWORD:-}"
        printf 'PORT_COUNT=%q\n' "$PORT_COUNT"

        local i
        for ((i = 0; i < PORT_COUNT; i++)); do
            printf 'LOCAL_PORT_%d=%q\n' "$((i + 1))" "${LOCAL_PORTS[$i]}"
            printf 'REMOTE_PORT_%d=%q\n' "$((i + 1))" "${REMOTE_PORTS[$i]}"
        done
    } > "$CONFIG_FILE"

    chmod 600 "$CONFIG_FILE"
    umask "$old_umask"

    success "Configuration saved to $CONFIG_FILE"
}

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Config file not found: $CONFIG_FILE"
        return 1
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    if [[ -z "${SSH_USER:-}" || -z "${SERVER_IP:-}" || -z "${AUTH_METHOD:-}" || -z "${PORT_COUNT:-}" ]]; then
        error "Config file is missing required fields."
        return 1
    fi

    OPERATION="${OPERATION:-port_forwarding}"
    if [[ "$OPERATION" != "port_forwarding" ]]; then
        error "Only port_forwarding is supported in --auto mode."
        return 1
    fi

    if [[ "$AUTH_METHOD" != "password" && "$AUTH_METHOD" != "key" ]]; then
        error "Invalid AUTH_METHOD in config. Expected 'password' or 'key'."
        return 1
    fi

    if ! [[ "$PORT_COUNT" =~ ^[0-9]+$ ]] || ((PORT_COUNT < 1)); then
        error "Invalid PORT_COUNT in config."
        return 1
    fi

    LOCAL_PORTS=()
    REMOTE_PORTS=()

    local i
    for ((i = 1; i <= PORT_COUNT; i++)); do
        local lp_var="LOCAL_PORT_$i"
        local rp_var="REMOTE_PORT_$i"
        local lp="${!lp_var:-}"
        local rp="${!rp_var:-}"

        if ! is_valid_port "$lp" || ! is_valid_port "$rp"; then
            error "Invalid port mapping in config for entry #$i."
            return 1
        fi

        LOCAL_PORTS+=("$lp")
        REMOTE_PORTS+=("$rp")
    done

    if [[ "$AUTH_METHOD" == "key" ]]; then
        if [[ -z "${KEY_PATH:-}" ]]; then
            error "KEY_PATH is missing in config for key authentication."
            return 1
        fi
    else
        if [[ -z "${PASSWORD:-}" ]]; then
            error "PASSWORD is missing in config for password authentication."
            return 1
        fi
    fi

    return 0
}

# -----------------------------
# Cron setup for auto-start
# -----------------------------
detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

install_cron_package() {
    local pm
    pm="$(detect_package_manager)"

    info "Installing cron package using detected package manager: $pm"

    case "$pm" in
        apt)
            if sudo apt-get update && sudo apt-get install -y cron; then
                return 0
            fi
            ;;
        yum)
            if sudo yum install -y cronie; then
                return 0
            fi
            ;;
        pacman)
            if sudo pacman -Sy --noconfirm cronie; then
                return 0
            fi
            ;;
        *)
            error "Unsupported package manager. Please install cron/cronie manually."
            return 1
            ;;
    esac

    error "Automatic cron installation failed."
    return 1
}

ensure_crontab_available_interactive() {
    if command -v crontab >/dev/null 2>&1; then
        return 0
    fi

    warn "crontab is not installed."
    if prompt_yes_no "crontab is not installed. Do you want to install it? (y/n): "; then
        if install_cron_package; then
            if command -v crontab >/dev/null 2>&1; then
                success "crontab is now available."
                return 0
            fi
            error "Installation completed, but crontab is still not found in PATH."
            return 1
        fi
        return 1
    fi

    warn "Skipping auto-start setup because crontab is unavailable."
    return 1
}

setup_reboot_cron() {
    require_tool crontab || return 1

    local script_path
    script_path="$(get_script_path)"

    local cron_line
    cron_line="@reboot /bin/bash \"$script_path\" --auto >> \"$LOG_DIR/auto-start.log\" 2>&1 $CRON_MARKER"

    local existing
    existing="$(crontab -l 2>/dev/null || true)"

    if echo "$existing" | grep -Fq "$CRON_MARKER"; then
        info "Auto-start cron job already exists. Skipping duplicate entry."
        return 0
    fi

    if { printf '%s\n' "$existing"; printf '%s\n' "$cron_line"; } | crontab -; then
        success "Auto-start cron job added. Tunnel will start on reboot."
        return 0
    else
        error "Failed to add cron job."
        return 1
    fi
}

# -----------------------------
# Interactive input flow
# -----------------------------
collect_connection_and_auth_config() {
    SSH_USER="$(prompt_non_empty 'Enter SSH username: ')"

    while true; do
        SERVER_IP="$(prompt_non_empty 'Enter remote server IP address: ')"
        if is_valid_ip "$SERVER_IP"; then
            break
        fi
        error "Invalid IP address format. Please enter a valid IPv4 address."
    done

    while true; do
        echo "Select authentication method:"
        echo "  1) Password"
        echo "  2) SSH key file"
        read -r -p "Choice (1 or 2): " auth_choice

        case "$auth_choice" in
            1)
                AUTH_METHOD="password"
                read -r -s -p "Enter SSH password: " PASSWORD
                echo
                if [[ -z "$PASSWORD" ]]; then
                    error "Password cannot be empty."
                else
                    KEY_PATH=""
                    break
                fi
                ;;
            2)
                AUTH_METHOD="key"
                PASSWORD=""
                while true; do
                    KEY_PATH="$(prompt_non_empty 'Enter full path to private key file: ')"
                    if [[ -f "$KEY_PATH" && -r "$KEY_PATH" ]]; then
                        break
                    fi
                    error "Key file does not exist or is not readable."
                done
                break
                ;;
            *)
                error "Invalid selection. Please choose 1 or 2."
                ;;
        esac
    done
}

collect_operation_choice() {
    while true; do
        echo "Select operation:"
        echo "  1) Port Forwarding"
        echo "  2) Copy Files to Remote Server"
        read -r -p "Choice (1 or 2): " op_choice

        case "$op_choice" in
            1)
                OPERATION="port_forwarding"
                return 0
                ;;
            2)
                OPERATION="file_transfer"
                return 0
                ;;
            *)
                error "Invalid selection. Please choose 1 or 2."
                ;;
        esac
    done
}

collect_port_forwarding_config() {
    while true; do
        read -r -p "How many ports do you want to forward? " PORT_COUNT
        if [[ "$PORT_COUNT" =~ ^[0-9]+$ ]] && ((PORT_COUNT > 0)); then
            break
        fi
        error "Please enter a valid positive number."
    done

    LOCAL_PORTS=()
    REMOTE_PORTS=()

    local i lp rp
    for ((i = 1; i <= PORT_COUNT; i++)); do
        while true; do
            read -r -p "Port mapping #$i - Local port: " lp
            if is_valid_port "$lp"; then
                break
            fi
            error "Invalid local port. Must be numeric between 1 and 65535."
        done

        while true; do
            read -r -p "Port mapping #$i - Remote port: " rp
            if is_valid_port "$rp"; then
                break
            fi
            error "Invalid remote port. Must be numeric between 1 and 65535."
        done

        LOCAL_PORTS+=("$lp")
        REMOTE_PORTS+=("$rp")
    done
}

collect_file_transfer_config() {
    while true; do
        LOCAL_SOURCE_PATH="$(prompt_non_empty 'Enter local file/directory path: ')"
        if [[ -e "$LOCAL_SOURCE_PATH" ]]; then
            break
        fi
        error "Local path does not exist: $LOCAL_SOURCE_PATH"
    done

    REMOTE_DEST_PATH="$(prompt_non_empty 'Enter remote destination path: ')"

    if prompt_yes_no "Use recursive copy (for directories)? (y/n): "; then
        USE_RECURSIVE="yes"
    else
        USE_RECURSIVE="no"
    fi

    if prompt_yes_no "Are elevated permissions (sudo) required on remote destination? (y/n): "; then
        NEED_REMOTE_SUDO="yes"
    else
        NEED_REMOTE_SUDO="no"
    fi
}

handle_autostart_prompt() {
    if prompt_yes_no "Do you want the tunnel to auto-start on system boot? (y/n): "; then
        save_config || return 1

        if ensure_crontab_available_interactive; then
            setup_reboot_cron || return 1
            return 0
        fi

        warn "Auto-start was not configured."
        return 0
    fi

    info "Auto-start not enabled."
    return 0
}

# -----------------------------
# Modes
# -----------------------------
run_interactive_mode() {
    require_tool ssh || return 1

    show_welcome

    collect_connection_and_auth_config
    collect_operation_choice

    case "$OPERATION" in
        port_forwarding)
            collect_port_forwarding_config
            if start_tunnel; then
                handle_autostart_prompt || return 1
            else
                return 1
            fi
            ;;
        file_transfer)
            collect_file_transfer_config
            copy_files || return 1
            ;;
        *)
            error "Unsupported operation: $OPERATION"
            return 1
            ;;
    esac
}

run_auto_mode() {
    require_tool ssh || return 1

    info "Running in --auto mode. Loading configuration..."
    load_config || return 1

    if [[ "$AUTH_METHOD" == "password" ]]; then
        require_tool sshpass || return 1
    fi

    start_tunnel
}

show_usage() {
    echo "Usage: $0 [--auto]"
    echo "  --auto   Start SSH tunnel from config.env without interactive prompts"
}

main() {
    ensure_directories || exit 1

    case "${1:-}" in
        --auto)
            run_auto_mode || exit 1
            ;;
        "")
            run_interactive_mode || exit 1
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
