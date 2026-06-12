#!/usr/bin/env bash
set -euo pipefail

# ── Utility functions ────────────────────────────────────────────────────────
err()  { printf 'ERROR: %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }
log()  { printf '==> %s\n' "$*"; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT

KERNEL_DIR="${KERNEL_DIR:-${REPO_ROOT}/linux}"
KERNEL_CONFIG="${KERNEL_CONFIG:-${SCRIPT_DIR}/kernel.config}"
ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
KERNEL_JOBS="${KERNEL_JOBS:-$(nproc)}"

if [[ "${KERNEL_DIR}" != /* ]]; then
    KERNEL_DIR="${REPO_ROOT}/${KERNEL_DIR}"
fi
if [[ "${KERNEL_CONFIG}" != /* ]]; then
    KERNEL_CONFIG="${REPO_ROOT}/${KERNEL_CONFIG}"
fi

readonly GENERATED_CONFIG="${KERNEL_DIR}/.config"

check_inputs() {
    [[ -d "${KERNEL_DIR}" ]] || die "Kernel source not found: ${KERNEL_DIR}"
    [[ -f "${KERNEL_CONFIG}" ]] || die "Kernel config fragment not found: ${KERNEL_CONFIG}"
    [[ -x "${KERNEL_DIR}/scripts/kconfig/merge_config.sh" ]] || \
        die "Kernel merge_config.sh is unavailable."
}

config_value() {
    local option="$1"
    local line

    line="$(grep -m1 "^${option}=" "${GENERATED_CONFIG}" || true)"
    if [[ -n "${line}" ]]; then
        printf '%s\n' "${line#*=}"
    elif grep -qx "# ${option} is not set" "${GENERATED_CONFIG}"; then
        printf 'n\n'
    else
        printf 'undef\n'
    fi
}

validate_config() {
    local option expected actual
    local failures=0

    while IFS='=' read -r option expected; do
        [[ "${option}" == CONFIG_* ]] || continue

        actual="$(config_value "${option}")"
        if [[ "${expected}" == "n" ]]; then
            [[ "${actual}" == "n" || "${actual}" == "undef" ]] && continue
        elif [[ "${actual}" == "${expected}" ]]; then
            continue
        fi

        err "${option} requested ${expected}, resolved to ${actual}"
        (( failures++ ))
    done < "${KERNEL_CONFIG}"

    (( failures == 0 )) || exit 1
}

check_inputs

log "Generating minimal ${ARCH} config from ${KERNEL_CONFIG}"
(
    cd "${KERNEL_DIR}"
    ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" \
        ./scripts/kconfig/merge_config.sh -n /dev/null "${KERNEL_CONFIG}"
)

validate_config

# NOTE: Process substitution errors are not caught by set -e.
# Acceptable here: values are only used for informational output.
read -r built_in modules < <(
    awk -F= '
        $2 == "y" { built_in++ }
        $2 == "m" { modules++ }
        END { print built_in + 0, modules + 0 }
    ' "${GENERATED_CONFIG}"
)
log "Config stats: ${built_in} built-in, ${modules} modules"
log "Building kernel Image (jobs=${KERNEL_JOBS})"
make -C "${KERNEL_DIR}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" \
    Image -j"${KERNEL_JOBS}"
