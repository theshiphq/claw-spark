#!/usr/bin/env bash
# lib/setup-mcp.sh -- Installs and configures MCP (Model Context Protocol) servers
# via mcporter. Gives the agent real capabilities: diagrams, memory, code execution.
set -euo pipefail

setup_mcp() {
    log_info "Setting up MCP servers (diagrams, memory, code execution)..."
    hr

    # ── Install mcporter (the MCP bridge for OpenClaw) ────────────────────────
    if ! check_command mcporter; then
        log_info "Installing mcporter (MCP bridge)..."
        if npm install -g mcporter@latest >> "${CLAWSPARK_LOG}" 2>&1; then
            log_success "mcporter installed."
        else
            # Try with sudo
            sudo npm install -g mcporter@latest >> "${CLAWSPARK_LOG}" 2>&1 || {
                log_warn "mcporter installation failed. MCP servers will not be available."
                log_info "Install manually: npm install -g mcporter"
                return 0
            }
            log_success "mcporter installed (via sudo)."
        fi
    else
        log_success "mcporter already installed."
    fi

    # ── Pre-install MCP server packages globally (avoids npx download on each call) ──
    log_info "Installing MCP server packages..."
    local -a mcp_packages=(
        "mermaid-mcp-server"
        "@modelcontextprotocol/server-memory"
        "@modelcontextprotocol/server-filesystem"
        "@modelcontextprotocol/server-sequential-thinking"
    )

    for pkg in "${mcp_packages[@]}"; do
        local short_name="${pkg##*/}"
        printf '  %s->%s Installing %s%s%s ... ' "${CYAN}" "${RESET}" "${BOLD}" "${short_name}" "${RESET}"
        if npm install -g "${pkg}" >> "${CLAWSPARK_LOG}" 2>&1; then
            printf '%s✓%s\n' "${GREEN}" "${RESET}"
        elif sudo npm install -g "${pkg}" >> "${CLAWSPARK_LOG}" 2>&1; then
            printf '%s✓%s\n' "${GREEN}" "${RESET}"
        else
            printf '%s✗%s\n' "${YELLOW}" "${RESET}"
        fi
    done

    # ── Create mcporter config ────────────────────────────────────────────────
    local mcporter_dir="${HOME}/.mcporter"
    mkdir -p "${mcporter_dir}"

    local mcporter_config="${mcporter_dir}/mcporter.json"
    local workspace="${HOME}/workspace"

    log_info "Configuring MCP servers..."

    python3 -c "
import json, os, sys

config_path = sys.argv[1]
workspace = sys.argv[2]
home = os.environ.get('HOME', '/home/saiyam')

# Load existing config or start fresh
cfg = {}
if os.path.exists(config_path):
    try:
        with open(config_path) as f:
            cfg = json.load(f)
    except (json.JSONDecodeError, IOError):
        cfg = {}

servers = cfg.get('mcpServers', {})

# 1. Mermaid -- diagrams, flowcharts, architecture, sequence diagrams
#    The agent says 'draw architecture' -> generates Mermaid code -> renders to PNG
servers['mermaid'] = {
    'command': 'npx',
    'args': ['-y', 'mermaid-mcp-server'],
    'env': {}
}

# 2. Memory -- persistent knowledge graph across sessions
#    The agent remembers user preferences, project context, past decisions
servers['memory'] = {
    'command': 'npx',
    'args': ['-y', '@modelcontextprotocol/server-memory'],
    'env': {}
}

# 3. Filesystem -- enhanced file operations for the workspace
#    Read, write, search, move files with proper permissions
servers['filesystem'] = {
    'command': 'npx',
    'args': ['-y', '@modelcontextprotocol/server-filesystem', workspace],
    'env': {}
}

# 4. Sequential Thinking -- structured reasoning for complex tasks
#    Helps the agent break down problems, plan before executing
servers['sequentialthinking'] = {
    'command': 'npx',
    'args': ['-y', '@modelcontextprotocol/server-sequential-thinking'],
    'env': {}
}

cfg['mcpServers'] = servers

with open(config_path, 'w') as f:
    json.dump(cfg, f, indent=2)

print(f'Configured {len(servers)} MCP servers')
" "${mcporter_config}" "${workspace}" 2>> "${CLAWSPARK_LOG}" || {
        log_warn "Failed to write mcporter config."
        return 0
    }

    # ── Verify config was written ────────────────────────────────────────────
    if [[ -f "${mcporter_config}" ]]; then
        local server_count
        server_count=$(python3 -c "
import json
with open('${mcporter_config}') as f:
    print(len(json.load(f).get('mcpServers', {})))
" 2>/dev/null || echo "0")
        log_success "MCP servers configured: ${server_count} server(s) in ${mcporter_config}"
    fi

    # ── Show what's available ─────────────────────────────────────────────────
    printf '\n'
    printf '  %s%sMCP Capabilities:%s\n' "${BOLD}" "${CYAN}" "${RESET}"
    printf '  %s*%s Mermaid     -- architecture diagrams, flowcharts, sequence diagrams\n' "${GREEN}" "${RESET}"
    printf '  %s*%s Memory      -- persistent knowledge graph across conversations\n' "${GREEN}" "${RESET}"
    printf '  %s*%s Filesystem  -- enhanced file read/write/search\n' "${GREEN}" "${RESET}"
    printf '  %s*%s Thinking    -- structured reasoning for complex multi-step tasks\n' "${GREEN}" "${RESET}"
    printf '\n'
    printf '  The agent can now create diagrams, remember context, and plan complex work.\n'
    printf '  Add more servers: %sclawspark mcp add <server-name>%s\n\n' "${CYAN}" "${RESET}"

    log_success "MCP setup complete."
}
