#!/bin/bash
# Set Arch Linux ARM mirrors for best performance
# Usage: sudo ./set-arm-mirrors.sh [country_code] [options]
# Options:
#   --force    Force overwrite existing mirrorlist
#   --backup   Create backup before changes
#   --auto     Auto-detect country from timezone
#   --test     Test mirror connectivity before applying
#   --help     Show this help message

MIRRORLIST_FILE="/etc/pacman.d/mirrorlist"
COUNTRY=""
FORCE=0
BACKUP=0
AUTO_DETECT=0
TEST_MIRRORS=0
VERBOSE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --backup)
      BACKUP=1
      shift
      ;;
    --auto)
      AUTO_DETECT=1
      shift
      ;;
    --test)
      TEST_MIRRORS=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    --help)
      echo "Usage: $0 [country_code] [options]"
      echo "Country codes: us, de, uk, fr, au, ca, jp, nl, se, dk, no, fi, it, es, br, in, cn, kr, sg"
      echo "Options:"
      echo "  --force    Force overwrite existing mirrorlist"
      echo "  --backup   Create backup before changes"
      echo "  --auto     Auto-detect country from timezone"
      echo "  --test     Test mirror connectivity before applying"
      echo "  --verbose  Enable verbose output"
      echo "  --help     Show this help message"
      exit 0
      ;;
    -*)
      echo "[ERROR] Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$COUNTRY" ]]; then
        COUNTRY="$1"
      else
        echo "[ERROR] Multiple country codes specified" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# Set default country or enable auto-detection
if [[ -z "$COUNTRY" ]]; then
  AUTO_DETECT=1
  COUNTRY="us" # fallback if auto-detection fails
fi

# Auto-detect country function
auto_detect_country() {
  local detected_country="us" # fallback

  # Try to detect from timezone
  if command -v timedatectl >/dev/null 2>&1; then
    local timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "")
    case "$timezone" in
      Europe/London | Europe/Edinburgh) detected_country="uk" ;;
      Europe/Berlin | Europe/Munich) detected_country="de" ;;
      Europe/Paris) detected_country="fr" ;;
      Europe/Amsterdam) detected_country="nl" ;;
      Europe/Stockholm) detected_country="se" ;;
      Europe/Copenhagen) detected_country="dk" ;;
      Europe/Oslo) detected_country="no" ;;
      Europe/Helsinki) detected_country="fi" ;;
      Europe/Rome | Europe/Milan) detected_country="it" ;;
      Europe/Madrid) detected_country="es" ;;
      Australia/*) detected_country="au" ;;
      America/Toronto | America/Montreal) detected_country="ca" ;;
      America/Sao_Paulo) detected_country="br" ;;
      Asia/Tokyo) detected_country="jp" ;;
      Asia/Seoul) detected_country="kr" ;;
      Asia/Singapore) detected_country="sg" ;;
      Asia/Kolkata | Asia/Mumbai) detected_country="in" ;;
      Asia/Shanghai | Asia/Beijing) detected_country="cn" ;;
      America/*) detected_country="us" ;;
    esac
  fi

  echo "$detected_country"
}

# Test mirror connectivity function
test_mirror_connectivity() {
  local mirror_url="$1"
  local test_url="${mirror_url//\$arch\/\$repo/aarch64\/core}"

  if [[ $VERBOSE -eq 1 ]]; then
    echo "[DEBUG] Testing connectivity to: $test_url"
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -s --connect-timeout 5 --max-time 10 "$test_url" >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=5 --tries=1 "$test_url" -O /dev/null 2>&1
  else
    return 0 # Assume available if no test tools
  fi
}

# Apply auto-detection if enabled
if [[ $AUTO_DETECT -eq 1 ]]; then
  COUNTRY=$(auto_detect_country)
  if [[ $VERBOSE -eq 1 ]]; then
    echo "[DEBUG] Auto-detected country: $COUNTRY"
  fi
fi

# List of fast Arch Linux ARM mirrors by country
# Primary and fallback mirrors for better reliability
case "$COUNTRY" in
  us)
    PRIMARY_MIRROR="http://us.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  de)
    PRIMARY_MIRROR="http://de.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  uk)
    PRIMARY_MIRROR="http://uk.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  fr)
    PRIMARY_MIRROR="http://fr.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  au)
    PRIMARY_MIRROR="http://au.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  ca)
    PRIMARY_MIRROR="http://ca.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://us.mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  jp)
    PRIMARY_MIRROR="http://jp.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  nl)
    PRIMARY_MIRROR="http://nl.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://de.mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  se)
    PRIMARY_MIRROR="http://se.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  dk)
    PRIMARY_MIRROR="http://dk.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://de.mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  no)
    PRIMARY_MIRROR="http://no.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://se.mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  fi)
    PRIMARY_MIRROR="http://fi.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://se.mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  it)
    PRIMARY_MIRROR="http://it.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://de.mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  es)
    PRIMARY_MIRROR="http://es.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://fr.mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  br)
    PRIMARY_MIRROR="http://br.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://us.mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  in)
    PRIMARY_MIRROR="http://in.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  cn)
    PRIMARY_MIRROR="http://cn.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  kr)
    PRIMARY_MIRROR="http://kr.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://jp.mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  sg)
    PRIMARY_MIRROR="http://sg.mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
  *)
    PRIMARY_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
    FALLBACK_MIRROR="http://us.mirror.archlinuxarm.org/\$arch/\$repo"
    ;;
esac

# Test mirrors if requested and select the best one
if [[ $TEST_MIRRORS -eq 1 ]]; then
  echo "[INFO] Testing mirror connectivity..."

  if test_mirror_connectivity "$PRIMARY_MIRROR"; then
    MIRROR="Server = $PRIMARY_MIRROR"
    if [[ $VERBOSE -eq 1 ]]; then
      echo "[DEBUG] Primary mirror available: $PRIMARY_MIRROR"
    fi
  elif test_mirror_connectivity "$FALLBACK_MIRROR"; then
    MIRROR="Server = $FALLBACK_MIRROR"
    echo "[WARN] Primary mirror unavailable, using fallback: $FALLBACK_MIRROR"
  else
    MIRROR="Server = $PRIMARY_MIRROR"
    echo "[WARN] Both mirrors appear unavailable, proceeding with primary anyway"
  fi
else
  MIRROR="Server = $PRIMARY_MIRROR"
fi

echo "[INFO] Selected ARM mirror for country '$COUNTRY': $MIRROR"

if [[ -f "$MIRRORLIST_FILE" && $FORCE -eq 0 && -z "${OMARCHY_FORCE_MIRROR_OVERWRITE:-}" ]]; then
  # Merge behavior: append the ARM mirror Server line only if not already present
  existing=$(grep -E '^\s*Server\s*=' "$MIRRORLIST_FILE" || true)
  if echo "$existing" | grep -F -q "$MIRROR"; then
    echo "[OK] ARM mirror already present in $MIRRORLIST_FILE; not changing file."
  else
    if [[ $BACKUP -eq 1 ]]; then
      sudo cp "$MIRRORLIST_FILE" "$MIRRORLIST_FILE.bak.$(date +%Y%m%d%H%M%S)"
      echo "[INFO] Backed up existing mirrorlist to $MIRRORLIST_FILE.bak.*"
    fi
    echo "$MIRROR" | sudo tee -a "$MIRRORLIST_FILE" >/dev/null
    echo "[OK] Appended ARM mirror to $MIRRORLIST_FILE: $MIRROR"
    echo "Updating package database..."
    sudo pacman -Syy
  fi
else
  # Force overwrite or mirrorlist missing -> write the single ARM server entry
  if [[ -f "$MIRRORLIST_FILE" && $BACKUP -eq 1 ]]; then
    sudo cp "$MIRRORLIST_FILE" "$MIRRORLIST_FILE.bak.$(date +%Y%m%d%H%M%S)"
    echo "[INFO] Backed up existing mirrorlist to $MIRRORLIST_FILE.bak.*"
  fi

  echo "$MIRROR" | sudo tee "$MIRRORLIST_FILE"
  echo "[OK] Set ARM mirror: $MIRROR"

  echo "Updating package database..."
  sudo pacman -Syy
fi
