#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Cryptographic High-Entropy Password & Secret Generator
#  Ensures 100% random, cryptographically secure passwords & tokens for databases.
# =============================================================================

set -euo pipefail

# Generate a cryptographically strong random password
# Arguments:
#   $1: Length (default: 32)
#   $2: Mode ('urlsafe' [default], 'complex', 'hex', 'alphanumeric', 'base64')
generate_secret() {
    local length="${1:-32}"
    local mode="${2:-urlsafe}"
    local result=""

    case "${mode}" in
        urlsafe)
            # URL-safe alphanumeric + safe symbols (does not break database connection strings or URI parsing)
            # Length: 32 chars => ~190 bits entropy
            if command -v openssl >/dev/null 2>&1; then
                result=$(openssl rand -base64 96 | tr -dc 'A-Za-z0-9._~-' | head -c "${length}")
            else
                result=$(head -c 128 /dev/urandom | tr -dc 'A-Za-z0-9._~-' | head -c "${length}")
            fi
            ;;
        complex)
            # High-complexity with full printable special characters
            if command -v openssl >/dev/null 2>&1; then
                result=$(openssl rand -base64 96 | tr -dc 'A-Za-z0-9!#%*+,-.:=?@_~' | head -c "${length}")
            else
                result=$(head -c 128 /dev/urandom | tr -dc 'A-Za-z0-9!#%*+,-.:=?@_~' | head -c "${length}")
            fi
            ;;
        alphanumeric)
            # Pure alphanumeric (letters + digits)
            if command -v openssl >/dev/null 2>&1; then
                result=$(openssl rand -base64 96 | tr -dc 'A-Za-z0-9' | head -c "${length}")
            else
                result=$(head -c 128 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c "${length}")
            fi
            ;;
        hex)
            # Hexadecimal token (e.g. for Master Keys, JWT secrets, Hash salts)
            if command -v openssl >/dev/null 2>&1; then
                result=$(openssl rand -hex "$(( (length + 1) / 2 ))" | head -c "${length}")
            else
                result=$(head -c "$(( (length + 1) / 2 ))" /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c "${length}")
            fi
            ;;
        base64)
            # Standard Base64
            if command -v openssl >/dev/null 2>&1; then
                result=$(openssl rand -base64 "$(( (length * 3) / 4 + 1 ))" | head -c "${length}")
            else
                result=$(head -c 64 /dev/urandom | base64 | tr -d '\n=' | head -c "${length}")
            fi
            ;;
        *)
            result=$(head -c 128 /dev/urandom | tr -dc 'A-Za-z0-9._~-' | head -c "${length}")
            ;;
    esac

    # Ensure length matches requested length exactly
    while [ "${#result}" -lt "${length}" ]; do
        local extra
        extra=$(head -c 32 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c "$(( length - ${#result} ))")
        result="${result}${extra}"
    done

    printf '%s' "${result}"
}

# If executed directly with arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    LENGTH="${1:-32}"
    MODE="${2:-urlsafe}"
    generate_secret "${LENGTH}" "${MODE}"
    printf '\n'
fi
