```
      ___  _      ___  __      __  ___  ___   ___   ___  _  __
     / __|| |    /   \ \ \    / / / __|| _ \ /   \ | _ \| |/ /
    | (__ | |__ | (_) | \ \/\/ /  \__ \|  _/| (_) ||   /| ' <
     \___||____| \___/   \_/\_/   |___/|_|   \___/ |_|_\|_|\_\

```

# clawspark

**One command. Private AI agent. Your hardware.**

```bash
curl -fsSL https://clawspark.dev/install.sh | bash
```

That's it. Go grab a coffee. Come back to a fully working, fully private AI agent that can code, research, browse the web, analyze images, and manage your tasks -- all running on your own hardware.

---

## What is this?

[OpenClaw](https://github.com/openclaw/openclaw) is the most popular open-source AI agent on the planet (247K+ stars). **clawspark** gets it running on your NVIDIA hardware in one command. Fully local. Fully private. Your data never leaves your machine. No cloud APIs, no subscriptions, no telemetry.

## What happens when you run it

1. **Detects your hardware** (DGX Spark, Jetson, RTX GPUs, Mac)
2. **Picks the best model** using [llmfit](https://github.com/AlexsJones/llmfit) for hardware-aware selection
3. **Installs everything** (Ollama, OpenClaw, skills, dependencies)
4. **Configures multi-model** (chat model + optional vision model for image analysis)
5. **Enables voice** (local Whisper transcription, zero cloud)
6. **Sets up browser automation** (headless Chromium for web tasks)
7. **Sets up your dashboard** (built-in chat UI + ClawMetry metrics)
8. **Creates systemd services** (auto-starts on boot, survives reboots)
9. **Hardens security** (firewall rules, auth tokens, localhost binding, optional Docker sandbox)

Total time: about 5 minutes on DGX Spark with a decent connection.

## Supported Hardware

**Tested and verified:**

| Hardware | Memory | Default Model | Tokens/sec |
|---|---|---|---|
| DGX Spark | 128 GB unified | Qwen 3.5 35B-A3B | ~59 (measured) |

DGX Spark has a curated model list tested on real hardware.

**Should work (community testing welcome):**

| Hardware | Memory | How to run |
|---|---|---|
| Jetson AGX Thor | 128 GB unified | SSH into Jetson, run the install command |
| Jetson AGX Orin | 64 GB unified | SSH into Jetson, run the install command |
| RTX 5090 / 4090 | 24 GB VRAM | Open a terminal on your desktop, run the install command |
| RTX 4080 / 4070 | 8-16 GB VRAM | Open a terminal on your desktop, run the install command |
| Mac M1/M2/M3/M4 | 16-128 GB unified | Open Terminal, run the install command |

NVIDIA platforms use [llmfit](https://github.com/AlexsJones/llmfit) to detect your hardware and recommend the best model that fits your VRAM/RAM, then verify it exists on Ollama before offering it. macOS uses the curated fallback list. All platforms require Ollama to be installed (the installer handles this).

**Not yet tested:** AMD GPUs, Intel Arc. PRs welcome.

## The 3 Questions

The installer asks you three things. That's it.

```
[1/3] Which model?
      > 5 models ranked by llmfit score + Ollama availability

[2/3] Connect a messaging platform? (Web UI is always available)
      > WhatsApp / Telegram / Both / Skip

[3/3] Set up Tailscale for remote access?
      > Yes (access from anywhere) / No
```

Want zero interaction? Use `--defaults`

```bash
curl -fsSL https://clawspark.dev/install.sh | bash -s -- --defaults
```

## What Your Agent Can Do

clawspark configures OpenClaw with the full tool suite. Your agent can:

| Capability | How it Works |
|---|---|
| **Answer questions** | Local LLM via Ollama, no cloud needed |
| **Search the web** | Built-in web search + DuckDuckGo fallback, no API key needed |
| **Deep research** | Sub-agents run parallel research threads |
| **Browse websites** | Headless Chromium automation (navigate, click, fill forms, screenshot) |
| **Analyze images** | Vision model (qwen2.5-vl or similar) for screenshots, photos, diagrams |
| **Write and run code** | exec + read/write/edit tools for full coding workflows |
| **Voice notes** | Local Whisper transcription, respond to WhatsApp voice messages |
| **File management** | Read, write, edit, search files on the host |
| **Scheduled tasks** | Cron-based automation (daily reports, monitoring, etc.) |
| **Sub-agent orchestration** | Spawn background agents for parallel tasks |

All of this runs locally. No data leaves your machine.

## Skills

Skills are OpenClaw plugins that give your agent new abilities. clawspark ships with 10 verified skills:

| Category | Skills |
|---|---|
| Core | local-whisper, self-improvement, memory-setup |
| Voice | whatsapp-voice-chat-integration-open-source |
| Productivity | deep-research-pro, agent-browser |
| Knowledge | second-brain, proactive-agent |
| Web Search | ddg-web-search, local-web-search-skill |

**Skill packs** -- install curated bundles for specific use cases:

```bash
clawspark skills pack research     # Deep research + web search (4 skills)
clawspark skills pack coding       # Code generation + review (2 skills)
clawspark skills pack productivity # Task management + knowledge (3 skills)
clawspark skills pack voice        # Voice interaction (2 skills)
clawspark skills pack full         # Everything (10 skills)
```

**Add or remove individual skills:**

```bash
clawspark skills add <name>
clawspark skills remove <name>
clawspark skills sync
clawspark skills audit            # Security scan all installed skills
```

## Multi-Model Support

clawspark configures three model slots:

| Slot | Purpose | Example |
|---|---|---|
| **Chat model** | Primary conversation and coding | `ollama/qwen3.5:35b-a3b` |
| **Vision model** | Image analysis and screenshots | `ollama/qwen2.5-vl:7b` |
| **Image generation** | Create images (optional, needs setup) | Local ComfyUI or API |

```bash
clawspark model list               # Show all models and their roles
clawspark model switch <model>     # Change the chat model
clawspark model vision <model>     # Set the vision model
```

## Docker Sandbox

Optional sandboxed code execution for sub-agents. When enabled, agent-spawned code runs in isolated Docker containers with:

- No network access (`--network=none`)
- Read-only root filesystem
- All capabilities dropped (`--cap-drop=ALL`)
- Custom seccomp profile blocking dangerous syscalls
- Memory and CPU limits

```bash
clawspark sandbox on       # Enable sandboxed execution
clawspark sandbox off      # Disable (run on host)
clawspark sandbox status   # Check sandbox configuration
clawspark sandbox test     # Verify sandbox works
```

## Voice Notes

Send a WhatsApp voice note to your agent. It gets transcribed locally using Whisper (no audio ever leaves your machine) and the agent responds to the text.

Whisper model size is matched to your hardware: large-v3 on DGX Spark, small on Jetson, base on RTX.

## Dashboard

clawspark gives you two web interfaces out of the box:

**Chat UI** (built into OpenClaw): `http://localhost:18789/__openclaw__/canvas/`
Talk to your AI agent directly from the browser.

**Metrics Dashboard** (ClawMetry): `http://localhost:8900`
Track token usage, agent activity, and model performance.

Both bind to localhost by default. Use Tailscale to access them securely from anywhere.

## Security

clawspark takes security seriously because your AI agent has access to your data.

- UFW firewall rules (only required ports open)
- Unique 256-bit auth token for the gateway API
- Gateway binds to localhost only
- Context-aware tool restrictions (full tools in DMs, Q&A only in groups)
- SOUL.md + TOOLS.md with absolute rules (no credential disclosure, no self-modification)
- Workspace files set to read-only (chmod 444)
- Plugin approval hooks (plugins must get user confirmation before acting)
- Optional Docker sandbox for code execution isolation
- Air-gap mode for complete network isolation: `clawspark airgap on`
- OpenAI-compatible API gateway (use your local AI as a drop-in OpenAI replacement)
- Skill security scanning against 341+ known malicious ClawHub patterns

### Skill Security Audit

OpenClaw's ClawHub marketplace has had malicious skills (data theft, credential exfiltration). clawspark protects you:

```bash
clawspark skills audit          # Scan all installed skills for suspicious patterns
```

The audit checks for network exfiltration, credential access, obfuscation, path traversal, and process spawning across 30+ patterns. Skills are verified against a curated allowlist, and file hashes are tracked to detect unexpected changes.

### Diagnostics

When something goes wrong, get a full system health report:

```bash
clawspark diagnose              # Full diagnostic (alias: clawspark doctor)
```

Checks hardware, GPU, Ollama, OpenClaw, skills, network ports, security config, and logs. Generates a shareable debug report at `~/.clawspark/diagnose-report.txt`.

## Service Management

All services auto-start on boot via systemd (Linux) or PID management (macOS).

```bash
clawspark start            # Start all services
clawspark stop             # Stop all services (keeps Ollama running)
clawspark stop --all       # Stop everything including Ollama
clawspark restart          # Restart all services
clawspark status           # Show health of all components
```

## Remote Access

clawspark can set up Tailscale during install for secure HTTPS access from any device on your Tailnet.

```bash
clawspark tailscale setup
```

## CLI

```bash
clawspark status             # Show system health and running services
clawspark start              # Start all services
clawspark stop               # Stop all services
clawspark restart            # Restart everything
clawspark update             # Update OpenClaw, re-apply patches
clawspark benchmark          # Run a performance benchmark
clawspark model list         # Show available models
clawspark model switch       # Change the active model
clawspark model vision       # Set or show the vision model
clawspark skills list        # Show installed skills
clawspark skills sync        # Apply skills.yaml changes
clawspark skills pack        # Install a curated skill bundle
clawspark skills audit       # Security scan installed skills
clawspark sandbox on|off     # Toggle Docker sandbox
clawspark sandbox status     # Show sandbox configuration
clawspark tools list         # Show available agent tools
clawspark tools enable       # Enable optional tools
clawspark tailscale setup    # Configure remote access
clawspark airgap on|off      # Toggle air-gap mode
clawspark diagnose           # Full system diagnostics (alias: doctor)
clawspark logs               # Tail all service logs
clawspark uninstall          # Remove everything
```

## Uninstall

```bash
clawspark uninstall
```

Removes all services, models, and configuration. Your conversation history is preserved in `~/.openclaw/backups/` unless you pass `--purge`.

## Acknowledgements

clawspark builds on the work of several excellent open-source projects:

- **[OpenClaw](https://github.com/openclaw/openclaw)** -- The AI agent framework that makes all of this possible
- **[Ollama](https://ollama.com)** -- Local LLM inference engine
- **[llmfit](https://github.com/AlexsJones/llmfit)** -- Hardware-aware model selection (by Alex Jones)
- **[Baileys](https://github.com/WhiskeySockets/Baileys)** -- WhatsApp Web client library
- **[Whisper](https://github.com/openai/whisper)** -- Open-source speech-to-text (by OpenAI)
- **[ClawMetry](https://github.com/vivekchand/clawmetry)** -- Observability dashboard for OpenClaw
- **[Qwen](https://github.com/QwenLM/Qwen)** -- The model family that runs beautifully on DGX Spark

## Testing

clawspark includes a test suite using [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System). 73 tests cover CLI routing, YAML parsing, security functions, and core utilities.

```bash
bash tests/run.sh
```

The test runner auto-installs bats if needed. Tests are organized into:

- `tests/common.bats` -- Logging, color constants, helpers (27 tests)
- `tests/skills.bats` -- YAML parsing, skill add/remove, packs (16 tests)
- `tests/security.bats` -- Token generation, permissions, deny lists (11 tests)
- `tests/cli.bats` -- Version, help, command routing, error handling (19 tests)

## Contributing

PRs welcome. The main areas where help is needed:
- Testing on different Jetson variants and RTX GPUs
- Hardware detection for more GPU models
- Additional messaging platform integrations
- New skills and skill packs
- Sandbox improvements

## License

MIT. See [LICENSE](LICENSE).

---

Built for people who want AI that works for them, not the other way around.

[clawspark.dev](https://clawspark.dev)
