#!/bin/sh
# shellcheck shell=dash

REPO="https://api.github.com/repos/yandexru45/netshift/releases/latest"
DOWNLOAD_DIR="/tmp/netshift"
COUNT=3

# Cached flag to switch between ipk or apk package managers
PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

rm -rf "$DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"

msg() {
    printf "\033[32;1m%s\033[0m\n" "$1"
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
        opkg install --force-downgrade --force-reinstall "$pkg_file"
    fi
}

update_config() {
    printf "\033[48;5;196m\033[1m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[48;5;196m\033[1m║ ! Обнаружена старая версия NetShift.                                 ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Если продолжите обновление, вам потребуется настроить NetShift заново.║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Старая конфигурация будет сохранена в /etc/config/netshift-070       ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Подробности: https://github.com/yandexru45/netshift                  ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Точно хотите продолжить?                                             ║\033[0m\n"
    printf "\033[48;5;196m\033[1m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n"

    echo ""

    printf "\033[48;5;196m\033[1m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[48;5;196m\033[1m║ ! Detected old NetShift version.                                     ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ If you continue the update, you will need to RECONFIGURE NetShift.   ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Your old configuration will be saved to /etc/config/netshift-070     ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Details: https://github.com/yandexru45/netshift                      ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Are you sure you want to continue?                                   ║\033[0m\n"
    printf "\033[48;5;196m\033[1m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n"

    msg "Continue? (yes/no)"

    while true; do
            read -r -p '' CONFIG_UPDATE
            case $CONFIG_UPDATE in

            yes|y|Y)
                mv /etc/config/netshift /etc/config/netshift-070
                wget -O /etc/config/netshift https://raw.githubusercontent.com/yandexru45/netshift/refs/heads/main/netshift/files/etc/config/netshift
                msg "NetShift config has been reset to default. Your old config saved in /etc/config/netshift-070"
                break
                ;;
            *)
                msg "Exit"
                exit 1
                ;;
        esac
    done
}

# Detect whether an OLD podkop install is present on this router.
# Returns 0 (true) if any podkop artifact is found.
podkop_is_installed() {
    if [ -f "/etc/config/podkop" ]; then
        return 0
    fi
    if command -v podkop >/dev/null 2>&1; then
        return 0
    fi
    if [ -x "/etc/init.d/podkop" ] || [ -f "/etc/init.d/podkop" ]; then
        return 0
    fi
    return 1
}

# Migrate an existing podkop (< 0.8.0) install to NetShift.
# podkop never reached 0.8.0, so any old podkop install triggers this.
# Every step is guarded by existence checks, POSIX, and idempotent so that
# re-running install.sh is safe.
migrate_from_podkop() {
    local old_version
    old_version=$(/usr/bin/podkop show_version 2>/dev/null)

    # 1. Bilingual banner (RU first, EN second) + confirmation prompt.
    printf "\033[48;5;196m\033[1m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[48;5;196m\033[1m║ ! Обнаружена установка podkop. Она будет перенесена в NetShift.      ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Ваша конфигурация будет перенесена автоматически.                   ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Старая конфигурация сохранится в /etc/config/podkop.bak.pre-netshift║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Старый пакет podkop будет удалён, NetShift будет установлен.         ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Подробности: https://github.com/yandexru45/netshift                  ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Точно хотите продолжить?                                             ║\033[0m\n"
    printf "\033[48;5;196m\033[1m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n"

    echo ""

    printf "\033[48;5;196m\033[1m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[48;5;196m\033[1m║ ! Detected a podkop install. It will be migrated to NetShift.        ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Your configuration will be carried over automatically.              ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Old config will be backed up to /etc/config/podkop.bak.pre-netshift ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ The old podkop package will be removed, NetShift installed.          ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Details: https://github.com/yandexru45/netshift                      ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Are you sure you want to continue?                                   ║\033[0m\n"
    printf "\033[48;5;196m\033[1m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n"

    if [ -n "$old_version" ]; then
        msg "Detected podkop version: $old_version"
    fi

    msg "Continue migration to NetShift? (yes/no)"

    read -r -p '' MIGRATE_CONFIRM
    case $MIGRATE_CONFIRM in
        yes|y|Y)
            ;;
        *)
            msg "Exit"
            exit 1
            ;;
    esac

    # 2. Stop the old service if running. The old 'stop' restores dnsmasq
    #    (podkop_server/noresolv/cachesize keys in /etc/config/dhcp), removes
    #    the old nft table PodkopTable and the '105 podkop' rt_tables line.
    #    Must run BEFORE removing the package for a clean teardown.
    if [ -x "/etc/init.d/podkop" ]; then
        msg "Stopping old podkop service..."
        /etc/init.d/podkop stop 2>/dev/null || true
    fi

    # 3. Disable old rc.d autostart (best-effort).
    if [ -x "/etc/init.d/podkop" ]; then
        msg "Disabling old podkop autostart..."
        /etc/init.d/podkop disable 2>/dev/null || true
    fi

    # 4. Migrate config (copy first, then remove the original — we keep a
    #    backup). Schema is compatible.
    if [ -f "/etc/config/podkop" ]; then
        if [ ! -f "/etc/config/netshift" ]; then
            msg "Migrating config /etc/config/podkop -> /etc/config/netshift..."
            cp /etc/config/podkop /etc/config/netshift 2>/dev/null || true
        else
            msg "/etc/config/netshift already exists, keeping it."
        fi
        if [ ! -f "/etc/config/podkop.bak.pre-netshift" ]; then
            cp /etc/config/podkop /etc/config/podkop.bak.pre-netshift 2>/dev/null || true
        fi
        # Remove the original /etc/config/podkop so a re-run does not keep
        # detecting an "old podkop install" (podkop_is_installed checks this
        # path). opkg/apk never delete user config, so we must do it here.
        # Only remove once the backup is confirmed present, to avoid data loss.
        if [ -f "/etc/config/podkop.bak.pre-netshift" ]; then
            msg "Removing migrated /etc/config/podkop (backup kept at podkop.bak.pre-netshift)..."
            rm -f /etc/config/podkop 2>/dev/null || true
        fi
    fi

    # 5. Migrate state dir (preserves subscription cache). Best-effort.
    if [ -d "/etc/podkop" ] && [ ! -d "/etc/netshift" ]; then
        msg "Migrating state dir /etc/podkop -> /etc/netshift..."
        cp -r /etc/podkop /etc/netshift 2>/dev/null || true
    fi

    # 6. Clean leftover OLD persistent system state that opkg/apk remove won't.
    #    rt_tables: remove old '105 podkop' line (NetShift adds '105 netshift'
    #    itself on start).
    if [ -f "/etc/iproute2/rt_tables" ] && grep -q "105 podkop" /etc/iproute2/rt_tables 2>/dev/null; then
        msg "Removing old '105 podkop' rt_tables entry..."
        sed -i "/105 podkop/d" /etc/iproute2/rt_tables 2>/dev/null || true
    fi
    #    Old cron lines: strip entries that call the old binary (NetShift re-adds
    #    its own on start).
    if crontab -l >/dev/null 2>&1; then
        if crontab -l 2>/dev/null | grep -q "/usr/bin/podkop"; then
            msg "Removing old podkop cron entries..."
            crontab -l 2>/dev/null | grep -v "/usr/bin/podkop" | crontab - 2>/dev/null || true
        fi
    fi
    #    NOTE: nft table PodkopTable + dnsmasq keys are cleaned by the
    #    '/etc/init.d/podkop stop' above; we do NOT hand-edit /etc/config/dhcp.

    # 7. Remove OLD packages (after config/state migrated).
    #    Order: i18n, then luci-app, then backend.
    if pkg_is_installed luci-i18n-podkop; then
        msg "Removing old luci-i18n-podkop* packages..."
        pkg_remove luci-i18n-podkop*
    fi
    if pkg_is_installed luci-app-podkop; then
        msg "Removing old luci-app-podkop package..."
        pkg_remove luci-app-podkop
    fi
    if pkg_is_installed "^podkop" || command -v podkop >/dev/null 2>&1; then
        msg "Removing old podkop package..."
        pkg_remove podkop
    fi

    # 8. Done.
    msg "Migration complete. NetShift will now be installed."
    msg "Your old config is preserved at /etc/config/podkop.bak.pre-netshift"
}

main() {
    check_system
    sing_box

    /usr/sbin/ntpd -q -p 194.190.168.1 -p 216.239.35.0 -p 216.239.35.4 -p 162.159.200.1 -p 162.159.200.123

    pkg_list_update || { echo "Packages list update failed"; exit 1; }

    if [ -f "/etc/init.d/netshift" ]; then
        msg "NetShift is already installed. Upgrading..."
    else
        msg "Installing NetShift..."
    fi

    if command -v curl >/dev/null 2>&1; then
        check_response=$(curl -s "https://api.github.com/repos/yandexru45/netshift/releases/latest")

        if echo "$check_response" | grep -q 'API rate limit '; then
            msg "You've reached the GitHub rate limit. Repeat in five minutes."
            exit 1
        fi
    fi

    local grep_url_pattern
    if [ "$PKG_IS_APK" -eq 1 ]; then
        grep_url_pattern='https://[^"[:space:]]*\.apk'
    else
        grep_url_pattern='https://[^"[:space:]]*\.ipk'
    fi

    wget -qO- "$REPO" | grep -o "$grep_url_pattern" | while read -r url; do
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
    if ! ls "$DOWNLOAD_DIR"/*netshift* >/dev/null 2>&1; then
        msg "No packages were downloaded successfully"
        exit 1
    fi

    for pkg in netshift luci-app-netshift; do
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
    for f in "$DOWNLOAD_DIR"/luci-i18n-netshift-ru*; do
        if [ -f "$f" ]; then
            ru=$(basename "$f")
            break
        fi
    done
    if [ -n "$ru" ]; then
        if pkg_is_installed luci-i18n-netshift-ru; then
                msg "Upgrading Russian translation..."
                pkg_remove luci-i18n-netshift*
                pkg_install "$DOWNLOAD_DIR/$ru"
        else
            msg "Русский язык интерфейса ставим? y/n (Install the Russian interface language?)"
            while true; do
                read -r -p '' RUS
                case $RUS in
                y)
                    pkg_remove luci-i18n-netshift*
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

    find "$DOWNLOAD_DIR" -type f -name '*netshift*' -exec rm {} \;
}

check_system() {
    # Get router model
    MODEL=$(cat /tmp/sysinfo/model)
    msg "Router model: $MODEL"

    # Check OpenWrt version
    openwrt_version=$(cat /etc/openwrt_release | grep DISTRIB_RELEASE | cut -d"'" -f2 | cut -d'.' -f1)
    if [ "$openwrt_version" = "23" ]; then
        msg "OpenWrt 23.05 не поддерживается начиная с NetShift 0.8.0"
        msg "Для OpenWrt 23.05 устанавливайте зависимости и NetShift вручную"
        msg "Подробности: https://podkop.net/docs/install/#%d1%83%d1%81%d1%82%d0%b0%d0%bd%d0%be%d0%b2%d0%ba%d0%b0-%d0%bd%d0%b0-2305"
        exit 1
    fi

    # Check available space
    AVAILABLE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
    REQUIRED_SPACE=15360 # 15MB in KB

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

    # Old podkop install detected -> migrate to NetShift before installing the
    # new packages. podkop never reached 0.8.0, so ANY old podkop triggers this.
    if podkop_is_installed; then
        migrate_from_podkop
        return
    fi

    # Otherwise check existing NetShift version (just upgrading NetShift).
    if command -v netshift > /dev/null 2>&1; then
        local version
        version=$(/usr/bin/netshift show_version 2> /dev/null)
        if [ -n "$version" ]; then
            version=$(echo "$version" | sed 's/^v//')
            local major
            local minor
            local patch
            major=$(echo "$version" | cut -d. -f1)
            minor=$(echo "$version" | cut -d. -f2)
            patch=$(echo "$version" | cut -d. -f3)

            # Compare version: must be >= 0.8.0
            if [ "$major" -gt 0 ] ||
                { [ "$major" -eq 0 ] && [ "$minor" -gt 8 ]; } ||
                { [ "$major" -eq 0 ] && [ "$minor" -eq 8 ] && [ "$patch" -ge 0 ]; }; then
                msg "NetShift version >= 0.8.0"
            else
                msg "NetShift version < 0.8.0"
                update_config
            fi
        else
            msg "Unknown NetShift version"
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
        service netshift stop 2>/dev/null || service podkop stop 2>/dev/null || true
        pkg_remove sing-box
    fi
}

main