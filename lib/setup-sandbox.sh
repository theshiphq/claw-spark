#!/usr/bin/env bash
# lib/setup-sandbox.sh -- Optional Docker-based sandbox for safe code execution.
# Enables OpenClaw to run agent-generated code in an isolated container.
# If Docker is not installed, the installer continues without sandbox support.
set -euo pipefail

setup_sandbox() {
    # Install Docker if not available
    if ! check_command docker; then
        log_info "Docker not found. Installing for sandboxed code execution..."
        if check_command apt-get; then
            # Linux: install via official Docker convenience script
            (curl -fsSL https://get.docker.com | sh) >> "${CLAWSPARK_LOG}" 2>&1 &
            spinner $! "Installing Docker..."
            if check_command docker; then
                # Add current user to docker group so we don't need sudo
                sudo usermod -aG docker "${USER}" 2>> "${CLAWSPARK_LOG}" || true
                # Start Docker daemon
                sudo systemctl start docker 2>> "${CLAWSPARK_LOG}" || true
                sudo systemctl enable docker 2>> "${CLAWSPARK_LOG}" || true
                log_success "Docker installed."
            else
                log_warn "Docker installation failed -- sandbox will not be available."
                return 0
            fi
        elif check_command brew; then
            log_info "Installing Docker via Homebrew..."
            (brew install --cask docker) >> "${CLAWSPARK_LOG}" 2>&1 &
            spinner $! "Installing Docker..."
            if [[ -d "/Applications/Docker.app" ]]; then
                log_success "Docker installed. Open Docker.app to start the daemon."
                log_warn "Docker daemon not running yet -- sandbox will be available after starting Docker."
                return 0
            else
                log_warn "Docker installation failed -- sandbox will not be available."
                return 0
            fi
        else
            log_warn "No package manager found -- install Docker manually for sandbox support."
            return 0
        fi
    fi

    # Check if Docker daemon is running
    if ! docker info &>/dev/null; then
        # Try to start it
        if check_command systemctl; then
            sudo systemctl start docker 2>> "${CLAWSPARK_LOG}" || true
            sleep 2
        fi
        if ! docker info &>/dev/null; then
            log_warn "Docker is installed but daemon is not running -- sandbox skipped."
            log_info "Start Docker and run: clawspark sandbox on"
            return 0
        fi
    fi

    log_info "Setting up Docker sandbox for safe code execution..."

    # ── Create sandbox directory and Dockerfile ───────────────────────────────
    local sandbox_dir="${CLAWSPARK_DIR}/sandbox"
    mkdir -p "${sandbox_dir}"

    cat > "${sandbox_dir}/Dockerfile" <<'DOCKERFILE'
FROM ubuntu:22.04

# Non-interactive apt
ENV DEBIAN_FRONTEND=noninteractive

# Install common dev tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    nodejs npm \
    git curl wget jq \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash sandbox
USER sandbox
WORKDIR /sandbox

# Set up Python virtual env
RUN python3 -m venv /sandbox/.venv
ENV PATH="/sandbox/.venv/bin:$PATH"

# Install common Python packages
RUN pip install --no-cache-dir \
    requests flask fastapi uvicorn \
    pandas numpy matplotlib \
    beautifulsoup4 lxml

CMD ["/bin/bash"]
DOCKERFILE

    # ── Seccomp profile (block dangerous syscalls) ────────────────────────────
    cat > "${sandbox_dir}/seccomp-profile.json" <<'SECCOMP'
{
    "defaultAction": "SCMP_ACT_ALLOW",
    "syscalls": [
        {
            "names": [
                "mount", "umount2", "pivot_root",
                "swapon", "swapoff",
                "reboot", "kexec_load", "kexec_file_load",
                "init_module", "finit_module", "delete_module",
                "acct", "settimeofday", "clock_settime",
                "ptrace",
                "add_key", "request_key", "keyctl",
                "unshare", "setns"
            ],
            "action": "SCMP_ACT_ERRNO",
            "errnoRet": 1
        }
    ]
}
SECCOMP

    # ── Build the sandbox image ───────────────────────────────────────────────
    log_info "Building sandbox image (this may take a minute)..."
    (docker build -t clawspark-sandbox:latest "${sandbox_dir}") >> "${CLAWSPARK_LOG}" 2>&1 &
    spinner $! "Building clawspark-sandbox image..."

    if docker image inspect clawspark-sandbox:latest &>/dev/null; then
        log_success "Sandbox image built: clawspark-sandbox:latest"
    else
        log_warn "Sandbox image build failed. Check ${CLAWSPARK_LOG}."
        return 0
    fi

    # NOTE: We do NOT write sandbox config to openclaw.json during install.
    # Setting agents.defaults.sandbox with network:"none" breaks the main agent's
    # network access. The sandbox image and seccomp profile are ready for use via
    # "clawspark sandbox on" which will enable it when the user explicitly wants it.
    # The sandbox run.sh helper works standalone without any openclaw.json changes.

    # Persist sandbox state as "off" (available but not active)
    echo "false" > "${CLAWSPARK_DIR}/sandbox.state"
    log_success "Sandbox image and seccomp profile ready."
    log_info "Enable later with: clawspark sandbox on"

    # ── Helper script for manual sandbox use ──────────────────────────────────
    cat > "${sandbox_dir}/run.sh" <<'RUNSH'
#!/usr/bin/env bash
# run.sh -- Run a command inside the clawspark sandbox.
# Usage: ~/.clawspark/sandbox/run.sh <command>
# Example: ~/.clawspark/sandbox/run.sh python3 -c "print('hello')"
set -euo pipefail

SANDBOX_DIR="${HOME}/.clawspark/sandbox"

if ! command -v docker &>/dev/null; then
    echo "Error: Docker is not installed." >&2
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "Error: Docker daemon is not running." >&2
    exit 1
fi

if ! docker image inspect clawspark-sandbox:latest &>/dev/null; then
    echo "Error: Sandbox image not found. Run install.sh or rebuild with:" >&2
    echo "  docker build -t clawspark-sandbox:latest ${SANDBOX_DIR}" >&2
    exit 1
fi

docker run --rm -it \
    --read-only \
    --tmpfs /tmp:size=100m \
    --tmpfs /sandbox/work:size=500m \
    --network=none \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --security-opt="seccomp=${SANDBOX_DIR}/seccomp-profile.json" \
    --memory=1g \
    --cpus=2 \
    --pids-limit=200 \
    -v "${PWD}:/sandbox/code:ro" \
    clawspark-sandbox:latest \
    "$@"
RUNSH
    chmod +x "${sandbox_dir}/run.sh"

    log_success "Sandbox setup complete."
    log_info "Sub-agent code execution will run in isolated Docker containers."
    log_info "Manual use: ~/.clawspark/sandbox/run.sh <command>"
}
