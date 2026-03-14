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
2. **Picks the best model** for your specific GPU and memory
3. **Installs everything** (Ollama, OpenClaw, skills, dependencies)
4. **Enables voice** (local Whisper transcription, zero cloud)
5. **Sets up your dashboard** (built-in chat UI + ClawMetry metrics)
6. **Hardens security** (firewall rules, auth tokens, localhost binding)

Total time: about 5 minutes on DGX Spark with a decent connection.

## Supported Hardware

| Hardware | Memory | Recommended Model | Tokens/sec |
|---|---|---|---|
| DGX Spark | 128 GB unified | Qwen 3.5 35B-A3B / 122B | ~59 |
| Jetson AGX Thor | 128 GB unified | Qwen 3.5 35B-A3B (MoE) | ~30 |
| Jetson AGX Orin | 64 GB unified | Nemotron 3 Nano 30B | ~25 |
| RTX 5090 / 4090 | 24 GB VRAM | Qwen 3.5 35B-A3B (Q4) | ~40 |
| RTX 4080 | 16 GB VRAM | GLM 4.7 Flash | ~35 |

All models run 100% locally. No cloud fallback by default.

## The 3 Questions

The installer asks you three things. That's it.

```
[1/3] Which model?
      > Balanced (recommended) / Quality / Lightweight

[2/3] Connect a messaging platform? (Web UI is always available)
      > WhatsApp / Telegram / Both / Skip

[3/3] Set up Tailscale for remote access?
      > Yes (access from anywhere) / No
```

Want zero interaction? Use `--defaults`

```bash
curl -fsSL https://clawspark.dev/install.sh | bash -s -- --defaults
```

This picks Balanced model + WhatsApp + no Tailscale.

## Skills

Skills are OpenClaw plugins that give your agent new abilities. clawspark ships with a curated default set in `configs/skills.yaml`:

| Category | Skills |
|---|---|
| Core | local-whisper, prompt-guard, self-improvement, memory-setup |
| Voice | whatsapp-voice-chat-integration-open-source |
| Productivity | remind-me, deep-research, agent-browser, coding-agent, excel |
| Knowledge | second-brain, proactive-agent |

**Add or remove skills:**

```bash
# Edit the config
nano configs/skills.yaml

# Apply changes
clawspark skills sync
```

You can also add community skills:

```yaml
skills:
  custom:
    - name: my-cool-skill
      source: https://github.com/user/my-cool-skill
```

## Voice Notes

Send a WhatsApp voice note to your agent. It gets transcribed locally using Whisper (no audio ever leaves your machine) and the agent responds to the text. It works the same way you'd text the agent, just talk instead.

Supported languages: everything Whisper supports (99+ languages).

```bash
# Check voice status
clawspark voice status

# Switch Whisper model (tiny/base/small/medium/large)
clawspark voice model large
```

## Dashboard

clawspark gives you two web interfaces out of the box:

**Chat UI** (built into OpenClaw): `http://localhost:18789/__openclaw__/canvas/`
Talk to your AI agent directly from the browser. Manage sessions, skills, and channels.

**Metrics Dashboard** (ClawMetry): `http://localhost:8900`
Track token usage, costs per session, agent activity, cron jobs, and model performance.

Both bind to localhost by default. Use Tailscale to access them securely from anywhere.

## Security

clawspark takes security seriously because your AI agent has access to your data.

**What the hardening does:**
- Sets up UFW firewall rules (only required ports open)
- Generates unique auth tokens for all services
- Enables encrypted storage for conversation history
- Configures Ollama to listen on localhost only
- Disables telemetry in all components

Air-gap mode is available for advanced users who need complete network isolation: `clawspark airgap on`

## Remote Access

clawspark can set up Tailscale during install, giving you secure HTTPS access from any device on your Tailnet.

Access your AI assistant from your phone in the USA while the DGX Spark runs at home. No port forwarding, no VPN configuration.

```bash
clawspark tailscale setup
```

## CLI

```bash
clawspark status           # Show system health and running services
clawspark start            # Start all services
clawspark stop             # Stop all services
clawspark restart          # Restart everything
clawspark update           # Update OpenClaw and skills
clawspark model list       # Show available models
clawspark model switch     # Change the active model
clawspark skills list      # Show installed skills
clawspark skills sync      # Apply skills.yaml changes
clawspark voice status     # Voice transcription status
clawspark voice model      # Switch Whisper model size
clawspark dashboard         # Open metrics dashboard
clawspark tailscale setup   # Configure Tailscale remote access
clawspark airgap on|off     # Toggle air-gap mode (advanced)
clawspark logs             # Tail all service logs
clawspark doctor           # Diagnose common issues
clawspark uninstall        # Remove everything
```

## Uninstall

```bash
clawspark uninstall
```

This removes all services, models, and configuration. Your conversation history is preserved in `~/.openclaw/backups/` unless you pass `--purge`.

## Contributing

PRs welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting.

The main areas where help is needed:
- Hardware detection for more GPU models
- Additional messaging platform integrations
- New skills
- Testing on different Jetson variants

## License

MIT. See [LICENSE](LICENSE).

---

Built for people who want AI that works for them, not the other way around.
