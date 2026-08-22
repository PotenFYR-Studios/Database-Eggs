#!/usr/bin/env bash
# =============================================================================
#  PotenFYR Studios - Cryptographic High-Entropy Password & Secret Generator
#  Ensures 100% random, cryptographically secure passwords & tokens for databases.
# =============================================================================

# Generate a cryptographically strong random password
# Arguments:
#   $1: Length (default: 32)
#   $2: Mode ('urlsafe' [default], 'complex', 'hex', 'alphanumeric', 'base64')
generate_secret() {
    local length="${1:-32}"
    local mode="${2:-urlsafe}"
    local result=""

    # Enforce minimum length of 16 for security
    [ "${length}" -lt 16 ] && length=16

    case "${mode}" in
        urlsafe)
            # URL-safe alphanumeric + safe symbols (does not break database connection strings or URI parsing)
            # 32 characters of [A-Za-z0-9._~-] provides ~190 bits of cryptographic entropy
            if command -v openssl >/dev/null 2>&1; then
                result=$(openssl rand -base64 96 | tr -dc 'A-Za-z0-9._~-' | head -c "${length}")
            else
                result=$(head -c 128 /dev/urandom | tr -dc 'A-Za-z0-9._~-' | head -c "${length}")
            fi
            ;;
        complex)
            # High-complexity with full printable special characters (~210 bits of entropy for 32 chars)
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

# Mask a secret string for safe logging (e.g. "AbCdEfGh" -> "Ab******Gh")
mask_secret() {
    local secret="${1:-}"
    local len="${#secret}"
    if [ "${len}" -le 6 ]; then
        printf '******'
    else
        local prefix="${secret:0:2}"
        local suffix="${secret: -2}"
        printf '%s******%s' "${prefix}" "${suffix}"
    fi
}

# If executed directly with arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    LENGTH="${1:-32}"
    MODE="${2:-urlsafe}"
    generate_secret "${LENGTH}" "${MODE}"
    printf '\n'
fi
