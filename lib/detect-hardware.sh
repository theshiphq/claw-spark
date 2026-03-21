#!/usr/bin/env bash
# lib/detect-hardware.sh — Detects GPU, CPU, and memory for platform classification.
# Exports: HW_PLATFORM, HW_GPU_NAME, HW_GPU_VRAM_MB, HW_TOTAL_RAM_MB,
#          HW_CPU_CORES, HW_CPU_ARCH, HW_DRIVER_VERSION
set -euo pipefail

detect_hardware() {
    log_info "Detecting hardware..."

    # ── CPU ─────────────────────────────────────────────────────────────────
    HW_CPU_ARCH=$(uname -m)

    if [[ -f /proc/cpuinfo ]]; then
        HW_CPU_CORES=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || nproc 2>/dev/null || echo 1)
    elif check_command sysctl; then
        HW_CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    else
        HW_CPU_CORES=1
    fi

    # ── Memory ──────────────────────────────────────────────────────────────
    if [[ -f /proc/meminfo ]]; then
        local mem_kb
        mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
        HW_TOTAL_RAM_MB=$(( mem_kb / 1024 ))
    elif check_command sysctl; then
        local mem_bytes
        mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        HW_TOTAL_RAM_MB=$(( mem_bytes / 1024 / 1024 ))
    else
        HW_TOTAL_RAM_MB=0
    fi

    # ── GPU / Platform detection ────────────────────────────────────────────
    HW_GPU_NAME="none"
    HW_GPU_VRAM_MB=0
    HW_DRIVER_VERSION="n/a"
    HW_PLATFORM="generic"

    # Check for Jetson (Tegra) first — it may not have nvidia-smi
    if [[ -f /etc/nv_tegra_release ]] || uname -r 2>/dev/null | grep -qi tegra; then
        HW_PLATFORM="jetson"
        HW_GPU_NAME="NVIDIA Jetson (Tegra)"
        # Jetson shares system memory; VRAM = total RAM
        HW_GPU_VRAM_MB="${HW_TOTAL_RAM_MB}"
        log_info "Jetson platform detected via Tegra signature."
    fi

    # Check for DGX Spark via DMI product name
    if [[ -f /sys/devices/virtual/dmi/id/product_name ]]; then
        local product_name
        product_name=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "")
        if echo "${product_name}" | grep -qiE "DGX.Spark|DGX_Spark"; then
            HW_PLATFORM="dgx-spark"
            log_info "DGX Spark detected via DMI product name."
        fi
    fi

    # nvidia-smi based detection
    if check_command nvidia-smi; then
        local gpu_info
        gpu_info=$(nvidia-smi --query-gpu=name,memory.total,driver_version \
                   --format=csv,noheader,nounits 2>/dev/null || echo "")

        if [[ -n "${gpu_info}" ]]; then
            # Take the first GPU line
            local first_gpu
            first_gpu=$(echo "${gpu_info}" | head -n1)

            HW_GPU_NAME=$(echo "${first_gpu}" | cut -d',' -f1 | xargs)
            local vram_str
            vram_str=$(echo "${first_gpu}" | cut -d',' -f2 | xargs)
            # Handle [N/A] or "Not Supported" (DGX Spark unified memory)
            if [[ "${vram_str}" =~ ^[0-9]+ ]]; then
                HW_GPU_VRAM_MB="${vram_str%%.*}"
            else
                HW_GPU_VRAM_MB=0
            fi
            HW_DRIVER_VERSION=$(echo "${first_gpu}" | cut -d',' -f3 | xargs)

            # Detect DGX Spark by GPU name (GB10 / Grace-Blackwell)
            if echo "${HW_GPU_NAME}" | grep -qiE "GB10|DGX.*Spark|Grace.*Blackwell"; then
                HW_PLATFORM="dgx-spark"
            fi

            # Detect RTX cards
            if [[ "${HW_PLATFORM}" == "generic" ]]; then
                if echo "${HW_GPU_NAME}" | grep -qiE "RTX|GeForce|Quadro"; then
                    HW_PLATFORM="rtx"
                fi
            fi
        fi
    fi

    # macOS with Apple Silicon: detect GPU via system_profiler
    if [[ "${HW_PLATFORM}" == "generic" && "$(uname)" == "Darwin" ]]; then
        local chip_info
        chip_info=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "")
        if echo "${chip_info}" | grep -qi "Apple"; then
            HW_PLATFORM="mac"
            HW_GPU_NAME="Apple Silicon (${chip_info})"
            # Apple Silicon uses unified memory; GPU VRAM = system RAM
            HW_GPU_VRAM_MB="${HW_TOTAL_RAM_MB}"
            HW_DRIVER_VERSION="Metal"
        fi
    fi

    # Unified memory platforms: VRAM = system RAM (nvidia-smi reports N/A)
    # This must come AFTER nvidia-smi parsing which may have reset VRAM to 0
    if [[ "${HW_PLATFORM}" == "dgx-spark" ]]; then
        HW_TOTAL_RAM_MB=131072   # 128 * 1024
        HW_GPU_VRAM_MB=131072
    elif [[ "${HW_PLATFORM}" == "jetson" && "${HW_GPU_VRAM_MB}" -eq 0 ]]; then
        # Jetson uses unified memory; nvidia-smi returns N/A for VRAM
        HW_GPU_VRAM_MB="${HW_TOTAL_RAM_MB}"
    fi

    # ── Validate NVIDIA driver version (Ollama needs >= 531 for GPU) ────────
    if [[ "${HW_DRIVER_VERSION}" != "n/a" && "${HW_DRIVER_VERSION}" != "Metal" ]]; then
        local driver_major
        driver_major=$(echo "${HW_DRIVER_VERSION}" | cut -d. -f1)
        if [[ "${driver_major}" =~ ^[0-9]+$ ]] && (( driver_major > 0 && driver_major < 531 )); then
            log_warn "NVIDIA driver ${HW_DRIVER_VERSION} is too old for GPU inference (need >= 531)."
            log_warn "Ollama will fall back to CPU-only mode. Update driver: sudo apt install nvidia-driver-535"
        fi
    fi

    # ── Export globals ──────────────────────────────────────────────────────
    export HW_PLATFORM HW_GPU_NAME HW_GPU_VRAM_MB HW_TOTAL_RAM_MB
    export HW_CPU_CORES HW_CPU_ARCH HW_DRIVER_VERSION

    # ── Pretty summary ──────────────────────────────────────────────────────
    local ram_gb=$(( HW_TOTAL_RAM_MB / 1024 ))
    local vram_gb=$(( HW_GPU_VRAM_MB / 1024 ))

    local platform_label
    case "${HW_PLATFORM}" in
        dgx-spark) platform_label="NVIDIA DGX Spark" ;;
        jetson)    platform_label="NVIDIA Jetson" ;;
        rtx)       platform_label="NVIDIA RTX Desktop" ;;
        mac)       platform_label="macOS Apple Silicon" ;;
        *)         platform_label="Generic / Unknown GPU" ;;
    esac

    print_box \
        "${BOLD}Hardware Summary${RESET}" \
        "" \
        "Platform    : ${CYAN}${platform_label}${RESET}" \
        "GPU         : ${HW_GPU_NAME}" \
        "VRAM        : ${vram_gb} GB" \
        "System RAM  : ${ram_gb} GB" \
        "CPU Cores   : ${HW_CPU_CORES}  (${HW_CPU_ARCH})" \
        "Driver      : ${HW_DRIVER_VERSION}"

    log_success "Hardware detection complete — platform: ${HW_PLATFORM}"
}
