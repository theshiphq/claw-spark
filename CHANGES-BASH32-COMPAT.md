# Summary of Changes: Bash 3.2 / macOS Compatibility

This document summarizes the edits made so that the claw-spark installer and scripts run on **macOS with the default Bash 3.2**, and remain **portable across Bash 3.2, 4.x, and 5.x**.

---

## 1. Detailed Summary of Changes

### 1.1 `lib/common.sh`

| Location | Before | After |
|----------|--------|--------|
| **New helper** (after line ~28) | — | Added `to_lower() { echo "$1" \| tr '[:upper:]' '[:lower:]'; }` |
| **`prompt_choice()`** (lines 70–109) | Used `local -n _options=$2` and `${_options[@]}`, `${_options[$i]}` | Uses `options_name="$2"` and `eval` for indirect array access: `eval "count=\${#${options_name}[@]}"`, `eval "opt=\${${options_name}[$i]}"`, etc. |
| **`prompt_yn()`** (answer normalization) | `answer="${answer,,}"` | `answer=$(to_lower "${answer}")` |

**Purpose:**  
- `local -n` (nameref) is Bash 4.3+. Replacing it with “array name + eval” allows the same behavior on Bash 3.2.  
- `${var,,}` (lowercase) is Bash 4+. Replacing with `tr` keeps behavior and works on all Bash versions.

### 1.2 `lib/select-model.sh`

| Location | Before | After |
|----------|--------|--------|
| **`_present_model_choices()`** (lines 188–230) | `local -n _ids=$1`, `local -n _names=$2`, `local -n _labels=$3` and direct `${_ids[$i]}`, `${_labels[$i]}`, etc. | Takes array **names** as `_ids_name`, `_names_name`, `_labels_name` and uses `eval` for reads/writes: `eval "SELECTED_MODEL_ID=\${${_ids_name}[$i]}"`, `eval "label_val=\${${_labels_name}[$i]}"`, and similar. |

**Purpose:** Same as above: avoid namerefs so the script runs on Bash 3.2 while keeping behavior identical on 4.x/5.x.

### 1.3 `install.sh`

| Location | Before | After |
|----------|--------|--------|
| **Step 5 – messaging** (line ~216) | `FLAG_MESSAGING="${FLAG_MESSAGING,,}"` | `FLAG_MESSAGING=$(to_lower "${FLAG_MESSAGING}")` |

**Purpose:** Lowercase the messaging choice in a way that works on Bash 3.2 (macOS default).

### 1.4 `lib/setup-messaging.sh`

| Location | Before | After |
|----------|--------|--------|
| **Messaging choice** (line ~18) | `messaging_choice="${messaging_choice,,}"` | `messaging_choice=$(to_lower "${messaging_choice}")` |

**Purpose:** Same as above; `to_lower` is available because this script is sourced after `common.sh`.

### 1.5 `lib/setup-voice.sh`

| Location | Before | After |
|----------|--------|--------|
| **Messaging variable** (line ~49) | `messaging="${messaging,,}"` | `messaging=$(to_lower "${messaging}")` |

**Purpose:** Same lowercase normalization without Bash 4+ syntax.

### 1.6 `uninstall.sh`

| Location | Before | After |
|----------|--------|--------|
| **remove_models** (line ~83) | `remove_models="${remove_models,,}"` | `remove_models=$(echo "${remove_models}" \| tr '[:upper:]' '[:lower:]')` |
| **revert_fw** (line ~139) | `revert_fw="${revert_fw,,}"` | `revert_fw=$(echo "${revert_fw}" \| tr '[:upper:]' '[:lower:]')` |

**Purpose:** `uninstall.sh` does not source `common.sh`, so it uses inline `tr` instead of `to_lower` to achieve the same lowercase behavior on Bash 3.2.

---

## 2. Purpose Behind the Changes

- **Run on macOS out of the box**  
  macOS ships with Bash 3.2 (`/bin/bash`). The original code used:
  - **Namerefs** (`local -n`) → Bash 4.3+
  - **Parameter expansion for case** (`${var,,}`) → Bash 4+

  So the installer failed on macOS with “invalid option” and “bad substitution”. The changes remove these features and use constructs that work in Bash 3.2.

- **Keep behavior the same**  
  - Menu behavior and default selection are unchanged.  
  - All case-insensitive comparisons still use lowercased values.

- **No new dependencies**  
  Only `eval`, `tr`, and standard Bash 3.2 features are used.

---

## 3. Portability Across Bash Versions

**Yes. The changes are portable across Bash 3.2, 4.x, and 5.x.**

| Construct used | Bash 3.2 | Bash 4.x / 5.x |
|----------------|----------|-----------------|
| `eval` for indirect array access | ✅ | ✅ |
| `tr '[:upper:]' '[:lower:]'` | ✅ (POSIX) | ✅ |
| `echo "$var" \| tr ...` | ✅ | ✅ |
| No `local -n` | ✅ (not needed) | ✅ (still valid) |
| No `${var,,}` | ✅ (not used) | ✅ (still valid elsewhere if needed) |

So:

- **Bash 3.2 (e.g. macOS):** Scripts run without “invalid option” or “bad substitution”.
- **Bash 4.x / 5.x (e.g. Linux, Homebrew bash):** Same behavior; no reliance on 4.3+ namerefs or 4+ case conversion in the modified code.

The chosen patterns are standard and safe across these versions.

---

**Files modified:**  
`install.sh`, `lib/common.sh`, `lib/select-model.sh`, `lib/setup-messaging.sh`, `lib/setup-voice.sh`, `uninstall.sh`  
**File added:** `CHANGES-BASH32-COMPAT.md` (this summary).
