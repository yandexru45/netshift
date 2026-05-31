#!/bin/sh
# shellcheck shell=dash

REPO_OWNER="spgsroot"
REPO_NAME="padkap-evolution"
GITHUB_REPO="$REPO_OWNER/$REPO_NAME"
RELEASE_API="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
RELEASE_PAGE="https://github.com/$GITHUB_REPO/releases/latest"
RAW_BASE="https://raw.githubusercontent.com/$GITHUB_REPO/refs/heads/main"
DOWNLOAD_DIR="/tmp/padkap"
COUNT=3

# Cached flag to switch between ipk or apk package managers
PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

rm -rf "$DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"

msg() {
    printf "\033[32;1m%s\033[0m\n" "$1"
}

err() {
    printf "\033[31;1m%s\033[0m\n" "$1" >&2
}

pkg_is_installed () {
    local pkg_name="$1"

    if [ "$PKG_IS_APK" -eq 1 ]; then
        # grep -q should work without change based on example from documentation
        # apk list --installed --providers dnsmasq
        # <dnsmasq> dnsmasq-full-2.90-r3 x86_64 {feeds/base/package/network/services/dnsmasq} (GPL-2.0) [installed]
        apk list --installed | grep -q "$pkg_name"
    else
        opkg list-installed | grep -q "$pkg_name"
    fi
}

pkg_remove() {
    local pkg_name="$1"

    if [ "$PKG_IS_APK" -eq 1 ]; then
        # TODO: check --force-depends flag
        # Nothing here: https://openwrt.org/docs/guide-user/additional-software/opkg-to-apk-cheatsheet
        apk del "$pkg_name"
    else
        opkg remove --force-depends "$pkg_name"
    fi
}

pkg_list_update() {
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk update
    else
        opkg update
    fi
}

pkg_install() {
    local pkg_file="$1"

    if [ "$PKG_IS_APK" -eq 1 ]; then
        # Can't install without flag based on info from documentation
        # If you're installing a non-standard (self-built) package, use the --allow-untrusted option:
        apk add --allow-untrusted "$pkg_file"
    else
        opkg install "$pkg_file"
    fi
}

update_config() {
    printf "\033[48;5;196m\033[1m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[48;5;196m\033[1m║ ! Обнаружена старая версия padkap.                                   ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Если продолжите обновление, вам потребуется настроить Padkap заново. ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Старая конфигурация будет сохранена в /etc/config/padkap-070         ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Подробности: https://github.com/spgsroot/padkap-evolution           ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Точно хотите продолжить?                                             ║\033[0m\n"
    printf "\033[48;5;196m\033[1m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n"

    echo ""

    printf "\033[48;5;196m\033[1m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[48;5;196m\033[1m║ ! Detected old padkap version.                                       ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ If you continue the update, you will need to RECONFIGURE padkap.     ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Your old configuration will be saved to /etc/config/padkap-070       ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Details: https://github.com/spgsroot/padkap-evolution                ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Are you sure you want to continue?                                   ║\033[0m\n"
    printf "\033[48;5;196m\033[1m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n"

    msg "Continue? (yes/no)"

    while true; do
            read -r -p '' CONFIG_UPDATE
            case $CONFIG_UPDATE in

            yes|y|Y)
                mv /etc/config/padkap /etc/config/padkap-070
                wget -O /etc/config/padkap "$RAW_BASE/padkap/files/etc/config/padkap"
                msg "Padkap config has been reset to default. Your old config saved in /etc/config/padkap-070"
                break
                ;;
            *)
                msg "Exit"
                exit 1
                ;;
        esac
    done
}

main() {
    check_system
    sing_box

    /usr/sbin/ntpd -q -p 194.190.168.1 -p 216.239.35.0 -p 216.239.35.4 -p 162.159.200.1 -p 162.159.200.123

    pkg_list_update || { echo "Packages list update failed"; exit 1; }

    if [ -f "/etc/init.d/padkap" ]; then
        msg "Padkap is already installed. Upgrading..."
    else
        msg "Installing padkap..."
    fi

    release_json="$DOWNLOAD_DIR/latest-release.json"
    msg "Fetching latest release metadata from $GITHUB_REPO..."
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$RELEASE_API" -o "$release_json"; then
            err "Failed to fetch latest release metadata from GitHub."
            err "Check releases manually: $RELEASE_PAGE"
            exit 1
        fi
    else
        if ! wget -q -O "$release_json" "$RELEASE_API"; then
            err "Failed to fetch latest release metadata from GitHub."
            err "Check releases manually: $RELEASE_PAGE"
            exit 1
        fi
    fi

    if grep -q 'API rate limit' "$release_json"; then
        err "You've reached the GitHub API rate limit. Repeat later or download packages manually: $RELEASE_PAGE"
        exit 1
    fi

    release_tag=$(grep '"tag_name":' "$release_json" | head -n 1 | cut -d'"' -f4)
    if [ -n "$release_tag" ]; then
        msg "Latest release: $release_tag"
    else
        err "Latest release was not found or response is invalid."
        err "Create a GitHub release first: $RELEASE_PAGE"
        exit 1
    fi

    local grep_url_pattern
    if [ "$PKG_IS_APK" -eq 1 ]; then
        grep_url_pattern='https://[^"[:space:]]*\.apk'
    else
        grep_url_pattern='https://[^"[:space:]]*\.ipk'
    fi

    grep '"browser_download_url":' "$release_json" | grep -o "$grep_url_pattern" | while read -r url; do
        filename=$(basename "$url")
        filepath="$DOWNLOAD_DIR/$filename"

        attempt=0
        while [ $attempt -lt $COUNT ]; do
            msg "Download $filename (count $((attempt+1)))..."
            if wget -q -O "$filepath" "$url"; then
                if [ -s "$filepath" ]; then
                    msg "$filename successfully downloaded"
                    break
                fi
            fi
            msg "Download error for $filename. Retrying..."
            rm -f "$filepath"
            attempt=$((attempt+1))
        done

        if [ $attempt -eq $COUNT ]; then
            msg "Failed to download $filename after $COUNT attempts"
        fi
    done

    # Check if any files were downloaded
    if ! ls "$DOWNLOAD_DIR"/*padkap* >/dev/null 2>&1; then
        err "No padkap packages were downloaded successfully for this package manager."
        err "Expected package extension: $([ "$PKG_IS_APK" -eq 1 ] && echo apk || echo ipk)"
        err "Release page: $RELEASE_PAGE"
        exit 1
    fi

    for pkg in padkap luci-app-padkap; do
        file=""
        for f in "$DOWNLOAD_DIR"/"$pkg"*; do
            if [ -f "$f" ]; then
                file=$(basename "$f")
                break
            fi
        done
        if [ -n "$file" ]; then
            msg "Installing $file..."
            pkg_install "$DOWNLOAD_DIR/$file"
            sleep 3
        fi
    done

    ru=""
    for f in "$DOWNLOAD_DIR"/luci-i18n-padkap-ru*; do
        if [ -f "$f" ]; then
            ru=$(basename "$f")
            break
        fi
    done
    if [ -n "$ru" ]; then
        if pkg_is_installed luci-i18n-padkap-ru; then
                msg "Upgrading Russian translation..."
                pkg_remove luci-i18n-padkap*
                pkg_install "$DOWNLOAD_DIR/$ru"
        else
            msg "Русский язык интерфейса ставим? y/n (Install the Russian interface language?)"
            while true; do
                read -r -p '' RUS
                case $RUS in
                y)
                    pkg_remove luci-i18n-padkap*
                    pkg_install "$DOWNLOAD_DIR/$ru"
                    break
                    ;;
                n)
                    break
                    ;;
                *)
                    echo "Введите y или n"
                    ;;
                esac
            done
        fi
    fi

    find "$DOWNLOAD_DIR" -type f -name '*padkap*' -exec rm {} \;
}

check_system() {
    # Get router model
    MODEL=$(cat /tmp/sysinfo/model)
    msg "Router model: $MODEL"

    # Check OpenWrt version
    openwrt_version=$(cat /etc/openwrt_release | grep DISTRIB_RELEASE | cut -d"'" -f2 | cut -d'.' -f1)
    if [ "$openwrt_version" = "23" ]; then
        msg "OpenWrt 23.05 не поддерживается начиная с padkap 0.5.0"
        msg "Для OpenWrt 23.05 используйте padkap версии 0.4.11 или устанавливайте зависимости и padkap вручную"
        msg "Подробности: https://github.com/spgsroot/padkap-evolution#readme"
        exit 1
    fi

    # Check available space
    AVAILABLE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
    REQUIRED_SPACE=15360 # 15MB in KB for first install

    if command -v padkap > /dev/null 2>&1 || [ -f "/etc/init.d/padkap" ]; then
        REQUIRED_SPACE=8192 # 8MB is enough for upgrades; packages are downloaded to /tmp
    fi

    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        msg "Error: Insufficient space in flash"
        msg "Available: $((AVAILABLE_SPACE/1024))MB"
        msg "Required: $((REQUIRED_SPACE/1024))MB"
        exit 1
    fi

    if ! nslookup google.com >/dev/null 2>&1; then
        msg "DNS is not working."
        exit 1
    fi

    # Check version
    if command -v padkap > /dev/null 2>&1; then
        local version
        version=$(/usr/bin/padkap show_version 2> /dev/null)
        if [ -n "$version" ]; then
            version=$(echo "$version" | sed 's/^v//')
            local major
            local minor
            local patch
            major=$(echo "$version" | cut -d. -f1)
            minor=$(echo "$version" | cut -d. -f2)
            patch=$(echo "$version" | cut -d. -f3)

            # Compare version: must be >= 0.7.0
            if [ "$major" -gt 0 ] ||
                [ "$major" -eq 0 ] && [ "$minor" -gt 7 ] ||
                [ "$major" -eq 0 ] && [ "$minor" -eq 7 ] && [ "$patch" -ge 0 ]; then
                msg "Padkap version >= 0.7.0"
                return 0
            else
                msg "Padkap version < 0.7.0"
                update_config
            fi
        else
            msg "Unknown padkap version"
            update_config
        fi
    fi

    if pkg_is_installed https-dns-proxy; then
        msg "Conflicting package detected: https-dns-proxy. Remove?"

        while true; do
                read -r -p '' DNSPROXY
                case $DNSPROXY in

                yes|y|Y)
                    pkg_remove luci-app-https-dns-proxy
                    pkg_remove https-dns-proxy
                    pkg_remove luci-i18n-https-dns-proxy*
                    break
                    ;;
                *)
                    msg "Exit"
                    exit 1
                    ;;
        esac
    done
    fi
}

sing_box() {
    if ! pkg_is_installed "^sing-box"; then
        return
    fi

    sing_box_version=$(sing-box version | head -n 1 | awk '{print $3}')
    required_version="1.12.4"

    if [ "$(printf '%s\n%s\n' "$sing_box_version" "$required_version" | sort -V | head -n 1)" != "$required_version" ]; then
        msg "sing-box version $sing_box_version is older than the required version $required_version."
        msg "Removing old version..."
        service padkap stop
        pkg_remove sing-box
    fi
}

main
