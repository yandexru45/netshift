# syntax=docker/dockerfile:1
# ──────────────────────────────────────────────────────────────────
# Padkap Evolution — OpenWrt Smoke Test Container
#
# Purpose:
#   Run padkap in an OpenWrt rootfs container to verify functionality
#   BEFORE deploying to a physical router.
#
# What this tests:
#   ✓ Dependency availability (sing-box, curl, jq, base64, dig)
#   ✓ UCI config parsing and validation
#   ✓ Shell script syntax (ash) — all sourced libraries
#   ✓ sing-box config generation (dry run)
#   ✓ Helper functions (HWID, URL parsing, IP validation)
#   ✓ Subscription URL handling
#   ✓ nftables rules syntax (table creation, rule generation)
#   ✓ dnsmasq config backup/restore
#   ✓ Service lifecycle (start/stop/reload)
#   ✓ Diagnostics (check_sing_box, check_nft_rules, global_check)
#
# Limitations (kernel-level features):
#   ✗ TProxy packet interception (needs real kernel + kmod-nft-tproxy)
#   ✗ Full sing-box runtime (needs real network interfaces)
#   ✗ Clash API WebSocket (needs running sing-box process)
#
# Usage:
#   docker compose -f tests/docker-compose.yml up --build
#   docker compose -f tests/docker-compose.yml run --rm padkap-test
# ──────────────────────────────────────────────────────────────────

# ── Stage 1: Загрузка официального чистого rootfs ─────────────────
FROM --platform=linux/amd64 alpine:latest AS builder
WORKDIR /rootfs
# Скачиваем и распаковываем оригинальный OpenWrt 24.10.6
RUN apk add --no-cache curl tar gzip && \
    curl -sSL https://downloads.openwrt.org/releases/24.10.6/targets/x86/64/openwrt-24.10.6-x86-64-rootfs.tar.gz | tar -xz

# ── Stage 2: Сборка финального контейнера ─────────────────────────
FROM scratch
# Переносим настоящую систему OpenWrt
COPY --from=builder /rootfs /

LABEL org.opencontainers.image.title="Padkap Evolution Test"
LABEL org.opencontainers.image.description="Official OpenWrt 24.10.6 rootfs for Padkap testing"

# Для корректной работы opkg внутри пустого Docker нужна эта директория
RUN mkdir -p /var/lock

# ── Install runtime dependencies ─────────────────────────────────
RUN opkg update && \
    opkg install \
        sing-box \
        curl \
        jq \
        coreutils-base64 \
        bind-dig \
        nftables \
    && rm -rf /var/opkg-lists/*

# ── Create padkap directory structure ─────────────────────────────
RUN mkdir -p /usr/lib/padkap \
    /tmp/sing-box/rulesets \
    /tmp/sing-box/subscriptions \
    /var/run

# ── Copy padkap source files ─────────────────────────────────────
# All shell scripts, config, and init files are mounted at runtime
# via docker-compose volumes. This image contains only the base OS
# and dependencies. See docker-compose.yml for bind mounts.

# ── Prepare a minimal /etc/config/padkap for testing ──────────────
# (real config will be mounted by docker-compose or entrypoint)
COPY padkap/files/etc/config/padkap /etc/config/padkap.test

# ── Pre-create /lib/functions paths (OpenWrt UCI stubs) ───────────
# The rootfs image may not include the full UCI subsystem.
# The entrypoint script handles this gracefully.

# ── Set up entrypoint ────────────────────────────────────────────
COPY tests/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /padkap
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["all"]
