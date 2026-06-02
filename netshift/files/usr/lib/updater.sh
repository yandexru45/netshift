# shellcheck shell=ash

# Runtime updater for sing-box-extended and stock sing-box.
# JSON parsing is done with jq (no ucode, no extra package deps).
# This file is sourced from /usr/bin/netshift, so log() is available.

SB_EXT_ARCH_SUFFIX=""
UPDATES_SING_BOX_EXTENDED_REPO="shtorm-7/sing-box-extended"

updates_log() {
    local message="$1"
    local level="${2:-info}"

    log "Updater: $message" "$level"
}

# Returns 0 if the system uses musl libc.
updates_system_uses_musl() {
    ls /lib/ld-musl-*.so* >/dev/null 2>&1 && return 0

    ldd --version 2>&1 | grep -qi 'musl'
}

# Reads a value from /etc/openwrt_release (e.g. DISTRIB_ARCH).
updates_read_openwrt_release_value() {
    local key="$1"

    [ -f /etc/openwrt_release ] || return 0
    sed -n "s/^${key}='\(.*\)'/\1/p" /etc/openwrt_release 2>/dev/null | head -n 1
}

# Resolves the sing-box-extended release asset arch suffix into SB_EXT_ARCH_SUFFIX.
# Returns 1 if the architecture is unsupported.
updates_resolve_sing_box_extended_arch_suffix() {
    local host_arch distrib_arch

    host_arch="$(uname -m 2>/dev/null || true)"
    distrib_arch="$(updates_read_openwrt_release_value "DISTRIB_ARCH")"

    case "$distrib_arch" in
    *mipsel* | *mipsle*) host_arch="mipsel" ;;
    *mips64el* | *mips64le*) host_arch="mips64el" ;;
    esac

    case "$host_arch" in
    aarch64) SB_EXT_ARCH_SUFFIX="arm64" ;;
    armv7*) SB_EXT_ARCH_SUFFIX="armv7" ;;
    armv6*) SB_EXT_ARCH_SUFFIX="armv6" ;;
    x86_64) SB_EXT_ARCH_SUFFIX="amd64" ;;
    i386 | i686) SB_EXT_ARCH_SUFFIX="386" ;;
    mips) SB_EXT_ARCH_SUFFIX="mips-softfloat" ;;
    mipsel | mipsle) SB_EXT_ARCH_SUFFIX="mipsle-softfloat" ;;
    mips64) SB_EXT_ARCH_SUFFIX="mips64" ;;
    mips64el | mips64le) SB_EXT_ARCH_SUFFIX="mips64le" ;;
    riscv64) SB_EXT_ARCH_SUFFIX="riscv64" ;;
    s390x) SB_EXT_ARCH_SUFFIX="s390x" ;;
    *) return 1 ;;
    esac
}

# Fetches the sing-box-extended GitHub releases JSON (echoes to stdout).
updates_fetch_sing_box_extended_releases() {
    local url response
    url="https://api.github.com/repos/${UPDATES_SING_BOX_EXTENDED_REPO}/releases?per_page=30"

    if command -v curl >/dev/null 2>&1; then
        response="$(curl -m 15 -sL "$url" 2>/dev/null)"
    fi
    if [ -z "$response" ] && command -v wget >/dev/null 2>&1; then
        response="$(wget -q -O- "$url" 2>/dev/null)"
    fi

    [ -n "$response" ] || return 1
    printf '%s' "$response"
}

# Picks the newest non-draft, non-prerelease, stable (no alpha/beta/rc) tag.
updates_extended_release_tag() {
    local json="$1"

    printf '%s' "$json" | jq -r '
        map(select((.draft != true) and (.prerelease != true)))
        | map(.tag_name)
        | map(select(. != null and . != ""))
        | map(select((ascii_downcase | test("alpha|beta|rc")) | not))
        | .[0] // empty
    ' 2>/dev/null
}

# Extracts the release object matching the given tag.
updates_extended_release_object() {
    local json="$1"
    local tag="$2"

    printf '%s' "$json" | jq -c --arg t "$tag" '
        map(select((.draft != true) and (.prerelease != true) and (.tag_name == $t)))
        | .[0] // empty
    ' 2>/dev/null
}

# Resolves the download URL for the matching asset of a release object.
updates_extended_asset_url() {
    local rel="$1"
    local suffix url

    if updates_system_uses_musl; then
        suffix="linux-${SB_EXT_ARCH_SUFFIX}-musl.tar.gz"
        url="$(printf '%s' "$rel" | jq -r --arg s "$suffix" '
            .assets // []
            | map(select(.name != null and (.name | endswith($s))))
            | .[0].browser_download_url // empty
        ' 2>/dev/null)"
        if [ -n "$url" ]; then
            printf '%s' "$url"
            return 0
        fi
    fi

    suffix="linux-${SB_EXT_ARCH_SUFFIX}.tar.gz"
    url="$(printf '%s' "$rel" | jq -r --arg s "$suffix" '
        .assets // []
        | map(select(.name != null and (.name | endswith($s))))
        | .[0].browser_download_url // empty
    ' 2>/dev/null)"
    if [ -n "$url" ]; then
        printf '%s' "$url"
        return 0
    fi

    return 1
}

# Downloads a URL to a file path (curl, fall back to wget). Returns 0 on success.
updates_download_to_file() {
    local url="$1"
    local dest="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -m 120 -fsSL "$url" -o "$dest" && [ -s "$dest" ] && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$url" && [ -s "$dest" ] && return 0
    fi

    return 1
}

# Restarts netshift if its init script is present (best-effort).
updates_restart_netshift() {
    if [ -x /etc/init.d/netshift ]; then
        updates_log "Restarting netshift after component change"
        /etc/init.d/netshift restart >/dev/null 2>&1 || true
    fi
}

# Downloads and installs sing-box-extended, replacing /usr/bin/sing-box.
# Echoes a JSON result on stdout.
updates_install_sing_box_extended() {
    local tmp_dir archive releases tag rel asset_url
    local binary_path cronet_path
    local backup_binary backup_cronet new_version

    if ! updates_resolve_sing_box_extended_arch_suffix; then
        updates_log "Unsupported architecture for sing-box-extended" "error"
        echo "{\"success\":false,\"message\":\"Unsupported architecture for sing-box-extended\"}"
        return 1
    fi

    releases="$(updates_fetch_sing_box_extended_releases)"
    if [ -z "$releases" ]; then
        updates_log "Failed to fetch sing-box-extended releases" "error"
        echo "{\"success\":false,\"message\":\"Failed to fetch sing-box-extended releases\"}"
        return 1
    fi

    tag="$(updates_extended_release_tag "$releases")"
    if [ -z "$tag" ]; then
        updates_log "Failed to resolve sing-box-extended release tag" "error"
        echo "{\"success\":false,\"message\":\"Failed to resolve sing-box-extended release tag\"}"
        return 1
    fi

    rel="$(updates_extended_release_object "$releases" "$tag")"
    asset_url="$(updates_extended_asset_url "$rel")"
    if [ -z "$asset_url" ]; then
        updates_log "Failed to resolve sing-box-extended asset for arch $SB_EXT_ARCH_SUFFIX" "error"
        echo "{\"success\":false,\"message\":\"Failed to resolve sing-box-extended asset\"}"
        return 1
    fi

    tmp_dir="$(mktemp -d /tmp/netshift-sbext.XXXXXX 2>/dev/null)"
    if [ -z "$tmp_dir" ]; then
        updates_log "Failed to create temporary directory" "error"
        echo "{\"success\":false,\"message\":\"Failed to create temporary directory\"}"
        return 1
    fi

    archive="$tmp_dir/sing-box-extended.tar.gz"
    updates_log "Downloading sing-box-extended $tag ($SB_EXT_ARCH_SUFFIX)"
    if ! updates_download_to_file "$asset_url" "$archive"; then
        rm -rf "$tmp_dir"
        updates_log "Failed to download sing-box-extended" "error"
        echo "{\"success\":false,\"message\":\"Failed to download sing-box-extended\"}"
        return 1
    fi

    binary_path="$(tar -tzf "$archive" 2>/dev/null | grep -E '(^|/)sing-box$' | sed -n '1p')"
    if [ -z "$binary_path" ]; then
        rm -rf "$tmp_dir"
        updates_log "sing-box binary not found in archive" "error"
        echo "{\"success\":false,\"message\":\"sing-box binary not found in archive\"}"
        return 1
    fi
    cronet_path="$(tar -tzf "$archive" 2>/dev/null | grep -E '(^|/)libcronet\.so$' | sed -n '1p')"

    backup_binary=""
    if [ -e /usr/bin/sing-box ]; then
        backup_binary="$tmp_dir/sing-box.backup"
        if ! cp -p /usr/bin/sing-box "$backup_binary"; then
            rm -rf "$tmp_dir"
            updates_log "Failed to backup current sing-box binary" "error"
            echo "{\"success\":false,\"message\":\"Failed to backup current sing-box binary\"}"
            return 1
        fi
        rm -f /usr/bin/sing-box
    fi

    backup_cronet=""
    if [ -n "$cronet_path" ] && [ -e /usr/lib/libcronet.so ]; then
        backup_cronet="$tmp_dir/libcronet.so.backup"
        if ! cp -p /usr/lib/libcronet.so "$backup_cronet"; then
            [ -n "$backup_binary" ] && mv -f "$backup_binary" /usr/bin/sing-box
            rm -rf "$tmp_dir"
            updates_log "Failed to backup current libcronet.so" "error"
            echo "{\"success\":false,\"message\":\"Failed to backup current libcronet.so\"}"
            return 1
        fi
        rm -f /usr/lib/libcronet.so
    fi

    if ! tar -xzf "$archive" -O "$binary_path" > /usr/bin/sing-box 2>/dev/null || [ ! -s /usr/bin/sing-box ]; then
        rm -f /usr/bin/sing-box
        [ -n "$backup_binary" ] && mv -f "$backup_binary" /usr/bin/sing-box
        [ -n "$backup_cronet" ] && mv -f "$backup_cronet" /usr/lib/libcronet.so
        rm -rf "$tmp_dir"
        updates_log "Failed to extract sing-box-extended binary" "error"
        echo "{\"success\":false,\"message\":\"Failed to extract sing-box-extended binary\"}"
        return 1
    fi
    chmod 0755 /usr/bin/sing-box

    if [ -n "$cronet_path" ]; then
        if ! tar -xzf "$archive" -O "$cronet_path" > /usr/lib/libcronet.so 2>/dev/null || [ ! -s /usr/lib/libcronet.so ]; then
            rm -f /usr/bin/sing-box /usr/lib/libcronet.so
            [ -n "$backup_binary" ] && mv -f "$backup_binary" /usr/bin/sing-box
            [ -n "$backup_cronet" ] && mv -f "$backup_cronet" /usr/lib/libcronet.so
            rm -rf "$tmp_dir"
            updates_log "Failed to extract libcronet.so" "error"
            echo "{\"success\":false,\"message\":\"Failed to extract libcronet.so\"}"
            return 1
        fi
        chmod 0644 /usr/lib/libcronet.so
    fi

    new_version="$(LD_LIBRARY_PATH=/usr/lib /usr/bin/sing-box version 2>/dev/null | head -1 | awk '{print $NF}')"
    case "$new_version" in
    *extended*) ;;
    *)
        rm -f /usr/bin/sing-box
        [ -n "$backup_binary" ] && mv -f "$backup_binary" /usr/bin/sing-box
        [ -n "$cronet_path" ] && rm -f /usr/lib/libcronet.so
        [ -n "$backup_cronet" ] && mv -f "$backup_cronet" /usr/lib/libcronet.so
        rm -rf "$tmp_dir"
        updates_log "Installed sing-box failed extended validation; previous binary restored" "error"
        echo "{\"success\":false,\"message\":\"Installed sing-box failed extended validation; previous binary restored\"}"
        return 1
        ;;
    esac

    rm -f "$backup_binary" "$backup_cronet"
    rm -rf "$tmp_dir"
    updates_restart_netshift
    updates_log "Installed sing-box-extended $new_version"
    echo "{\"success\":true,\"version\":\"$new_version\"}"
    return 0
}

# Reinstalls the stock (stable) sing-box via the system package manager.
# Echoes a JSON result on stdout.
updates_install_sing_box_stable() {
    local new_version

    if command -v apk >/dev/null 2>&1; then
        updates_log "Updating apk package lists"
        apk update </dev/null >/dev/null 2>&1 || true
        updates_log "Installing stable sing-box via apk"
        if ! apk add --allow-downgrade sing-box </dev/null >/dev/null 2>&1; then
            apk fix sing-box </dev/null >/dev/null 2>&1 || true
        fi
    elif command -v opkg >/dev/null 2>&1; then
        updates_log "Updating opkg package lists"
        opkg update </dev/null >/dev/null 2>&1 || true
        updates_log "Installing stable sing-box via opkg"
        if ! opkg install --force-reinstall --force-downgrade sing-box </dev/null >/dev/null 2>&1; then
            opkg install --force-downgrade sing-box </dev/null >/dev/null 2>&1 || true
        fi
    else
        updates_log "No supported package manager (apk/opkg) found" "error"
        echo "{\"success\":false,\"message\":\"No supported package manager found\"}"
        return 1
    fi

    updates_restart_netshift
    new_version="$(get_sing_box_version)"
    updates_log "Stable sing-box installed: ${new_version:-unknown}"
    echo "{\"success\":true,\"version\":\"$new_version\"}"
    return 0
}

# Checks whether a newer sing-box-extended release is available.
# Echoes a JSON status (latest|outdated) on stdout.
updates_check_sing_box_extended() {
    local current_version releases tag status

    current_version="$(get_sing_box_version)"

    releases="$(updates_fetch_sing_box_extended_releases)"
    if [ -z "$releases" ]; then
        echo "{\"success\":false,\"message\":\"Failed to fetch sing-box-extended releases\"}"
        return 1
    fi

    tag="$(updates_extended_release_tag "$releases")"
    if [ -z "$tag" ]; then
        echo "{\"success\":false,\"message\":\"Failed to resolve sing-box-extended release tag\"}"
        return 1
    fi

    status="outdated"
    case "$current_version" in
    *"$tag"*) status="latest" ;;
    esac

    echo "{\"success\":true,\"current_version\":\"$current_version\",\"latest_version\":\"$tag\",\"status\":\"$status\"}"
    return 0
}

# Dispatcher for component-related actions.
component_action() {
    local component="$1"
    local action="$2"

    case "$component:$action" in
    sing_box:install_extended)
        updates_install_sing_box_extended
        ;;
    sing_box:install_stable)
        updates_install_sing_box_stable
        ;;
    sing_box:check_update)
        updates_check_sing_box_extended
        ;;
    *)
        echo '{"success":false,"message":"Unknown component action"}'
        return 1
        ;;
    esac
}
