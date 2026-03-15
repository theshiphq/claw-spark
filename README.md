```
      ___  _      ___  __      __  ___  ___   ___   ___  _  __
     / __|| |    /   \ \ \    / / / __|| _ \ /   \ | _ \| |/ /
    | (__ | |__ | (_) | \ \/\/ /  \__ \|  _/| (_) ||   /| ' <
     \___||____| \___/   \_/\_/   |___/|_|   \___/ |_|_\|_|\_\

```

# clawspark

**One command. Private AI assistant. Your hardware.**

```bash
curl -fsSL https://clawspark.dev/install.sh | bash
```

That's it. Go grab a coffee. Come back to a fully working, fully private AI assistant.

---

## What is this?

[OpenClaw](https://github.com/openclaw/openclaw) is the most popular open-source AI agent on the planet (247K+ stars). **clawspark** gets it running on your NVIDIA hardware in one command. Fully local. Fully private. Your data never leaves your machine. No cloud APIs, no subscriptions, no telemetry.

## What happens when you run it

1. **Detects your hardware** (DGX Spark, Jetson, RTX GPUs)
2. **Picks the best model** using [llmfit](https://github.com/AlexsJones/llmfit) for hardware-aware selection
3. **Installs everything** (Ollama, OpenClaw, skills, dependencies)
4. **Enables voice** (local Whisper transcription, zero cloud)
5. **Sets up your dashboard** (built-in chat UI + ClawMetry metrics)
6. **Hardens security** (firewall rules, auth tokens, localhost binding)

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

These platforms use [llmfit](https://github.com/AlexsJones/llmfit) to detect your hardware and recommend the best model that fits your VRAM/RAM, then verify it exists on Ollama before offering it. Requirements: Linux with NVIDIA drivers and CUDA installed, `nvidia-smi` working.

**Not yet supported:** macOS (Apple Silicon), AMD GPUs, Intel Arc. PRs welcome.

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

## Skills

Skills are OpenClaw plugins that give your agent new abilities. clawspark ships with 10 verified skills:

| Category | Skills |
|---|---|
| Core | local-whisper, self-improvement, memory-setup |
| Voice | whatsapp-voice-chat-integration-open-source |
| Productivity | deep-research-pro, agent-browser |
| Knowledge | second-brain, proactive-agent |
| Web Search | ddg-web-search, local-web-search-skill |

**Add or remove skills:**

```bash
clawspark skills add <name>
clawspark skills remove <name>
clawspark skills sync
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
- Air-gap mode for complete network isolation: `clawspark airgap on`

## Remote Access

clawspark can set up Tailscale during install for secure HTTPS access from any device on your Tailnet.

```bash
clawspark tailscale setup
```

## CLI

```bash
clawspark status           # Show system health and running services
clawspark start            # Start all services
clawspark stop             # Stop all services
clawspark restart          # Restart everything
clawspark update           # Update OpenClaw, re-apply patches
clawspark benchmark        # Run a performance benchmark
clawspark model list       # Show available models
clawspark model switch     # Change the active model
clawspark skills list      # Show installed skills
clawspark skills sync      # Apply skills.yaml changes
clawspark tools list       # Show available agent tools
clawspark tools enable     # Enable optional tools
clawspark voice status     # Voice transcription status
clawspark voice model      # Switch Whisper model size
clawspark tailscale setup  # Configure remote access
clawspark airgap on|off    # Toggle air-gap mode
clawspark logs             # Tail all service logs
clawspark doctor           # Diagnose common issues
clawspark uninstall        # Remove everything
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

## Contributing

PRs welcome. The main areas where help is needed:
- Testing on different Jetson variants
- Hardware detection for more GPU models
- Additional messaging platform integrations
- New skills

## License

MIT. See [LICENSE](LICENSE).

---

Built for people who want AI that works for them, not the other way around.

[clawspark.dev](https://clawspark.dev)
