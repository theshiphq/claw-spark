# Setting Up Your Private AI Assistant on DGX Spark

A step-by-step guide to getting OpenClaw running on your DGX Spark with clawspark. By the end of this tutorial, you'll have a fully private AI assistant that you can talk to over WhatsApp or Telegram, with voice note support and local transcription.

## 1. Prerequisites

Before you start, make sure you have:

- **DGX Spark** running DGX OS (Ubuntu-based). Other NVIDIA hardware works too, but this tutorial focuses on Spark.
- **Internet connection** for setup and for WhatsApp/Telegram to work. AI processing is fully local.
- **A phone** with WhatsApp and/or Telegram installed.
- **SSH access** or a terminal session on your DGX Spark.

Check that your system is ready:

```bash
# Verify NVIDIA drivers are loaded
nvidia-smi

# Verify you have enough disk space (need ~50GB free)
df -h /
```

## 2. Running the Installer

Open a terminal on your DGX Spark and run:

```bash
curl -fsSL https://clawspark.dev/install.sh | bash
```

You'll see output like this:

```
   clawspark installer v1.0

   Detecting hardware... DGX Spark (128GB unified memory)
   Architecture: aarch64
   CUDA version: 12.8

   Ready to install. This will set up:
     - Ollama (local model server)
     - OpenClaw (AI agent framework)
     - Default skills (13 skills)
     - Security hardening

   Continue? [Y/n]
```

Press Enter (or type `Y`) to continue. The installer will start downloading and configuring everything.

**What's happening behind the scenes:**
1. Ollama gets installed and configured for your hardware
2. The recommended model gets pulled (this is the longest step, usually 2-3 minutes on a fast connection)
3. OpenClaw gets installed with Node.js dependencies
4. Skills from `configs/skills.yaml` get installed
5. Firewall rules and auth tokens get configured
6. Services get registered with systemd

## 3. Choosing Your Model

The installer will ask you to pick a model tier:

```
[1/3] Which model?

  > balanced    Qwen 3.5 35B-A3B (MoE, ~59 tok/s)
                Only 3B active parameters. Fast and smart.

    quality     Qwen 3.5 122B (~20 tok/s)
                Full 122B model. Best reasoning, uses more memory.

    lightweight GLM 4.7 Flash (~60 tok/s)
                Compact and fast. Great for quick tasks.
```

**When to pick what:**

- **Balanced (recommended for most people):** The Qwen 3.5 35B-A3B is a Mixture of Experts model. It has 35 billion total parameters but only activates 3 billion per inference. This means you get the knowledge of a large model with the speed of a small one. On DGX Spark, it runs at about 59 tokens per second (verified on real hardware), which feels very responsive.

- **Quality:** The Qwen 3.5 122B is a full 122-billion-parameter model. It produces the best reasoning and most nuanced outputs, but it uses significantly more memory (81GB). Pick this if you care most about output quality and are okay with slower responses for complex tasks. On DGX Spark with 128GB, it fits comfortably.

- **Lightweight:** GLM 4.7 Flash is the smallest and fastest option. It runs at about 60 tokens per second on DGX Spark. Pick this if you mainly want quick answers, simple tasks, or if you plan to run other GPU workloads alongside the agent.

You can always switch models later:

```bash
clawspark model switch
```

## 4. Connecting WhatsApp

If you selected WhatsApp as your messaging platform, the installer will show you a QR code in the terminal:

```
[WhatsApp Setup]

Scan this QR code with WhatsApp on your phone:

  +---------------------------+
  |  [QR CODE APPEARS HERE]   |
  |                           |
  |  Open WhatsApp > Settings |
  |  > Linked Devices > Link  |
  +---------------------------+

Waiting for scan...
```

**Step by step:**

1. Open WhatsApp on your phone
2. Go to **Settings** (gear icon on iOS, three dots on Android)
3. Tap **Linked Devices**
4. Tap **Link a Device**
5. Point your camera at the QR code in the terminal
6. Wait a few seconds for the connection to establish

Once connected, you'll see:

```
WhatsApp connected successfully!
Send a message to yourself to test.
```

The way it works: the agent runs as a linked device on your WhatsApp account. You message yourself (or a dedicated number if you set one up) and the agent responds. All messages are processed locally on your DGX Spark.

**Important notes:**
- The QR code expires after about 60 seconds. If it expires, the installer will generate a new one.
- Your WhatsApp session persists across reboots. You only need to scan once.
- If you ever need to re-link, run `clawspark messaging reconnect whatsapp`.

## 5. Connecting Telegram

If you selected Telegram, you'll need to create a bot first:

```
[Telegram Setup]

You need a Telegram Bot Token. Here's how to get one:

1. Open Telegram and search for @BotFather
2. Send /newbot
3. Choose a name (e.g., "My Private AI")
4. Choose a username (must end in "bot", e.g., "my_private_ai_bot")
5. Copy the token BotFather gives you

Paste your bot token:
```

**Step by step:**

1. Open Telegram on your phone or desktop
2. Search for `@BotFather` and start a chat
3. Send `/newbot`
4. BotFather will ask for a display name. Type something like `My DGX Assistant`
5. BotFather will ask for a username. Type something like `my_dgx_assistant_bot` (must end in `bot`)
6. BotFather will reply with a token that looks like `7123456789:AAH1234567890abcdefghijklmnop`
7. Copy that token and paste it into the installer

After pasting the token:

```
Telegram bot connected!
Bot username: @my_dgx_assistant_bot
Send /start to your bot in Telegram to begin.
```

Now open Telegram, find your bot by its username, and send `/start`. The agent will respond and you're good to go.

**Restricting access:** By default, the bot only responds to your Telegram user ID. The installer detects this automatically when you send the first message. To allow other users, edit `~/.openclaw/openclaw.json` and add their Telegram user IDs to the `allowed_users` list.

## 6. Testing Voice Notes

Once setup is complete, test voice transcription:

1. Open WhatsApp (or Telegram)
2. Go to your agent's chat
3. Hold the microphone button and record a short message, something like "What's the weather like today?"
4. Send the voice note

You should see the agent respond within a few seconds. Behind the scenes:

1. The voice note arrives on your DGX Spark
2. Whisper transcribes it locally (no audio is sent to any cloud service)
3. The transcribed text gets passed to the AI model
4. The model's response gets sent back to your chat

**Check that voice is working:**

```bash
clawspark voice status
```

Expected output:

```
Voice transcription: active
Whisper model: base
Language: auto-detect
Average transcription time: 1.2s (for 10s audio)
```

**Upgrade the Whisper model for better accuracy:**

```bash
# Options: tiny, base, small, medium, large
clawspark voice model large
```

The `large` model gives the best transcription quality but uses more memory and is slower. On DGX Spark with 128GB, you can easily run the `large` model alongside your main AI model. On hardware with less memory, stick with `base` or `small`.

## 7. Customizing Skills

Skills are plugins that extend what your agent can do. The defaults are defined in `configs/skills.yaml`.

**View installed skills:**

```bash
clawspark skills list
```

**Remove a skill you don't need:**

Open `configs/skills.yaml` and delete or comment out the skill:

```yaml
skills:
  enabled:
    # - name: excel                    # commented out, won't be installed
    #   description: Read and write Excel files
    - name: deep-research
      description: Multi step research with planning
```

Then apply:

```bash
clawspark skills sync
```

**Add a community skill:**

Find a skill you want from the OpenClaw skill directory, then add it to the `custom` section:

```yaml
skills:
  custom:
    - name: home-assistant-control
      source: https://github.com/someuser/openclaw-home-assistant
      description: Control Home Assistant devices
```

Run `clawspark skills sync` to install it.

**Add a local skill you're developing:**

```yaml
skills:
  custom:
    - name: my-custom-skill
      source: /home/user/my-skill
      description: My custom skill
```

## 8. Dashboard and Metrics

clawspark sets up two web interfaces for you:

**Chat UI** (built into OpenClaw): `http://localhost:18789`
This is the primary way to interact with your AI agent from a browser. You can chat, manage sessions, view skills, and monitor channels. It works immediately after install.

**Metrics Dashboard** (ClawMetry): `http://localhost:8900`
This tracks token usage, costs per session, agent activity, cron jobs, and model performance. Useful for understanding how your agent is being used.

```bash
# Open the dashboard
clawspark dashboard

# Check status of both services
clawspark status
```

**Remote access with Tailscale:**

If you set up Tailscale during install, both dashboards are accessible from any device on your Tailnet. This means you can check your agent's metrics from your phone while traveling.

```bash
# Set up Tailscale if you skipped it during install
clawspark tailscale setup

# Check your Tailscale URLs
clawspark tailscale status
```

**Note for advanced users:** Air-gap mode is available via `clawspark airgap on` if you need complete network isolation. This blocks all outbound traffic and disables WhatsApp/Telegram (since they need internet). Only the local Chat UI and direct API access will work in air-gap mode.

## 9. Managing with the CLI

Here are the commands you'll use most often:

**Check if everything is running:**

```bash
clawspark status
```

This shows the health of all services (Ollama, OpenClaw, messaging bridges, Whisper).

**View logs when something seems off:**

```bash
# All logs
clawspark logs

# Just the AI model logs
clawspark logs ollama

# Just OpenClaw logs
clawspark logs openclaw
```

**Restart after a config change:**

```bash
clawspark restart
```

**Update to the latest version of OpenClaw:**

```bash
clawspark update
```

This pulls the latest OpenClaw release and updates skills. Your configuration and conversation history are preserved.

**Run diagnostics if something breaks:**

```bash
clawspark doctor
```

This checks GPU drivers, service health, port availability, disk space, and model integrity. It will tell you exactly what's wrong and suggest fixes.

**Switch models without reinstalling:**

```bash
# See what's available
clawspark model list

# Switch to a different model
clawspark model switch qwen3:80b
```

## 10. Troubleshooting

### "Ollama not responding"

```bash
# Check if Ollama is running
clawspark status

# Restart Ollama specifically
sudo systemctl restart ollama

# Check Ollama logs
clawspark logs ollama
```

Common cause: the model is still loading into memory. On first start after a reboot, the model needs to be loaded into GPU memory, which can take 30-60 seconds for large models.

### "WhatsApp disconnected"

The WhatsApp linked device session can expire if the phone is offline for more than 14 days.

```bash
# Check connection status
clawspark messaging status

# Re-link WhatsApp (will show new QR code)
clawspark messaging reconnect whatsapp
```

### "Voice notes not transcribing"

```bash
# Check Whisper status
clawspark voice status

# Re-download the Whisper model
clawspark voice model base --force
```

Common cause: not enough GPU memory for both the AI model and Whisper simultaneously. Try switching to a smaller Whisper model (`tiny` or `base`) or a lighter AI model.

### "Out of memory" errors

On DGX Spark with 128GB, this is rare. But if you're running the 80B quality model plus the large Whisper model plus other GPU workloads, you might hit the limit.

```bash
# Check memory usage
nvidia-smi

# Switch to a lighter model
clawspark model switch glm4.7:flash
```

### "Skills not working after sync"

```bash
# Check skill status
clawspark skills list

# Look for errors in the sync
clawspark skills sync --verbose

# Restart OpenClaw to pick up changes
clawspark restart
```

### "Can't reach the agent from another device on my network"

By default, clawspark configures Ollama to listen on `localhost` only for security. If you want to access it from other devices on your local network:

```bash
# Open the config
nano ~/.openclaw/openclaw.json

# Change the bind address from 127.0.0.1 to 0.0.0.0
# Then restart
clawspark restart
```

Make sure you understand the security implications before doing this. Anyone on your network will be able to access the agent.

### General tips

- Always run `clawspark doctor` first. It catches 90% of issues.
- Check `clawspark logs` for error messages.
- Make sure your DGX Spark firmware is up to date.
- If all else fails, `clawspark uninstall && curl -fsSL https://clawspark.dev/install.sh | bash` gives you a clean start without losing conversation history.
