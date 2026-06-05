#!/bin/sh
# ──────────────────────────────────────────────────────────────────
# Netshift Evolution — Smoke Test Suite Entrypoint
#
# Runs validation tests against the netshift codebase in an OpenWrt
# rootfs container. Designed for CI and pre-deployment verification.
# ──────────────────────────────────────────────────────────────────

set -e

# ── Colors ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0
RESULTS_DIR="${RESULTS_DIR:-/tmp/test-results}"
NETSHIFT_SRC="${NETSHIFT_SRC:-/netshift/files}"
NETSHIFT_LIB_DIR="${NETSHIFT_SRC}/usr/lib"

mkdir -p "$RESULTS_DIR"

# ── Helpers ─────────────────────────────────────────────────────
header() {
    printf "\n${BOLD}${CYAN}━━━ %s ━━━${NC}\n" "$1"
}

pass() {
    PASS=$((PASS + 1))
    printf "  ${GREEN}✓${NC} %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "  ${RED}✗${NC} %s\n" "$1"
    if [ -n "$2" ]; then
        printf "    ${RED}→${NC} %s\n" "$2"
    fi
}

skip() {
    SKIP=$((SKIP + 1))
    printf "  ${YELLOW}⊘${NC} %s (skipped)\n" "$1"
}

summary() {
    printf "\n${BOLD}──────────────────────────────────────${NC}\n"
    printf "Results: ${GREEN}%d passed${NC}" "$PASS"
    printf " / ${RED}%d failed${NC}" "$FAIL"
    if [ "$SKIP" -gt 0 ]; then
        printf " / ${YELLOW}%d skipped${NC}" "$SKIP"
    fi
    printf "\n"
    if [ "$FAIL" -gt 0 ]; then
        printf "${RED}${BOLD}✗ TESTS FAILED${NC} ($FAIL failure(s))\n"
        exit 1
    else
        printf "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC} ($PASS test(s))\n"
        exit 0
    fi
}

# ─────────────────────────────────────────────────────────────────
# Test: Dependency Check
# ─────────────────────────────────────────────────────────────────
test_deps() {
    header "Dependency Check"

    for bin in sing-box curl jq base64 dig nft ash; do
        if command -v "$bin" > /dev/null 2>&1; then
            pass "$bin is available ($(command -v "$bin"))"
        else
            fail "$bin is NOT available"
        fi
    done

    # Version checks
    if command -v sing-box > /dev/null 2>&1; then
        local sb_ver
        sb_ver=$(sing-box version 2>/dev/null | head -1 | awk '{print $NF}')
        if [ -n "$sb_ver" ]; then
            pass "sing-box version: $sb_ver"
        else
            fail "sing-box version detection failed"
        fi
    fi

    if command -v jq > /dev/null 2>&1; then
        local jq_ver
        jq_ver=$(jq --version 2>/dev/null | awk -F- '{print $2}')
        if [ -n "$jq_ver" ]; then
            pass "jq version: $jq_ver"
        else
            fail "jq version detection failed"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────
# Test: Shell Syntax & Loading
# ─────────────────────────────────────────────────────────────────
test_syntax() {
    header "Shell Syntax & Library Loading"

    local lib="${NETSHIFT_LIB_DIR}"

    # Test each library file for syntax errors
    for f in \
        "$lib/constants.sh" \
        "$lib/helpers.sh" \
        "$lib/logging.sh" \
        "$lib/nft.sh" \
        "$lib/rulesets.sh" \
        "$lib/sing_box_config_manager.sh" \
        "$lib/sing_box_config_facade.sh" \
        "$lib/updater.sh"; do

        if [ ! -r "$f" ]; then
            fail "File not found: $f"
            continue
        fi

        if ash -n "$f" 2>&1; then
            pass "Syntax OK: $(basename "$f")"
        else
            fail "Syntax ERROR in $(basename "$f")" "$(ash -n "$f" 2>&1)"
        fi
    done

    # Parse-check the CLI dispatcher itself (not just the libs).
    local cli="${NETSHIFT_SRC}/usr/bin/netshift"
    if [ ! -r "$cli" ]; then
        fail "File not found: $cli"
    elif ash -n "$cli" 2>&1; then
        pass "Syntax OK: $(basename "$cli")"
    else
        fail "Syntax ERROR in $(basename "$cli")" "$(ash -n "$cli" 2>&1)"
    fi

    # Guard against re-introduction of the task-004 double-encode mojibake
    # (UTF-8 emoji/box-drawing read as CP1251 and re-saved as UTF-8). The
    # corrupted bytes render as рџ… / в”… / вЂ…; build the byte markers with
    # printf octal escapes (busybox sed/grep lack \x).
    if [ -r "$cli" ]; then
        local mojibake_found=0
        local marker
        for marker in '\321\200\321\237' '\320\262\342\200\235' '\320\262\320\202'; do
            if grep -qF "$(printf "$marker")" "$cli" 2>/dev/null; then
                mojibake_found=1
            fi
        done
        if [ "$mojibake_found" -eq 0 ]; then
            pass "netshift CLI free of double-encode mojibake"
        else
            fail "netshift CLI contains residual mojibake (рџ/в”/вЂ)"
        fi
    fi

    # Test that libraries can be sourced (requires /lib/functions stubs).
    # Use a temp script to avoid fragile shell quoting.
    local source_test="/tmp/netshift-source-test-$$.sh"
    cat > "$source_test" << EOF
NETSHIFT_LIB="$lib"
NETSHIFT_CONFIG="/etc/config/netshift.test"
mkdir -p /lib/config /lib/functions
touch /etc/config/dhcp /etc/config/sing-box
. "$lib/logging.sh" 2>/dev/null && echo "OK"
EOF

    if ash "$source_test" 2>&1 | grep -q "OK"; then
        pass "logging.sh can be sourced"
    else
        skip "logging.sh source test (needs OpenWrt /lib/functions)"
    fi
    rm -f "$source_test"
}

# ─────────────────────────────────────────────────────────────────
# Test: UCI Config Validation
# ─────────────────────────────────────────────────────────────────
test_config() {
    header "UCI Config Validation"

    local config="${NETSHIFT_SRC}/etc/config/netshift"

    if [ ! -r "$config" ]; then
        fail "Config file not found: $config"
        return
    fi

    pass "Config file exists: $config"

    # Check for required sections
    if grep -q "config settings" "$config"; then
        pass "settings section present"
    else
        fail "settings section missing"
    fi

    if grep -q "config section" "$config"; then
        pass "section (proxy) present"
    else
        fail "section (proxy) missing"
    fi

    # Check that core options exist
    for opt in "shutdown_correctly" "dns_type" "connection_type" "proxy_config_type"; do
        if grep -q "option $opt" "$config"; then
            pass "option $opt present"
        else
            fail "option $opt missing"
        fi
    done

    # Count sections
    local section_count
    section_count=$(grep -c "^config section\|^#config section" "$config")
    pass "Sections in config: $section_count"
}

# ─────────────────────────────────────────────────────────────────
# Test: Helper Functions
# ─────────────────────────────────────────────────────────────────
test_helpers() {
    header "Helper Functions"

    local helpers="${NETSHIFT_LIB_DIR}/helpers.sh"

    if [ ! -r "$helpers" ]; then
        fail "helpers.sh not found"
        return
    fi

    # Write test script to a temp file to avoid quoting issues
    local tmp="/tmp/test-helpers-$$.sh"
    cat > "$tmp" << 'TESTEOF'
mkdir -p /lib/config /lib/functions /tmp/sysinfo
echo 'OpenWrt Test' > /tmp/sysinfo/model
touch /etc/config/dhcp /etc/config/sing-box

. "HELPERS_PATH"

# Test is_ipv4
is_ipv4 '192.168.1.1' && echo 'ipv4:OK' || echo 'ipv4:FAIL'
is_ipv4 'not-an-ip' && echo 'ipv4-bad:FAIL' || echo 'ipv4-bad:OK'

# Test url_is_ipv6_literal (our fork's IPv6 helper; expects a full URL with a bracketed host)
url_is_ipv6_literal 'http://[::1]:443/test' && echo 'ipv6-literal:OK' || echo 'ipv6-literal:FAIL'
url_is_ipv6_literal 'https://example.com:8080/path' && echo 'ipv6-literal-neg:FAIL' || echo 'ipv6-literal-neg:OK'

# Test is_ipv4_ip_or_ipv4_cidr
is_ipv4_ip_or_ipv4_cidr '10.0.0.0/8' && echo 'ipv4cidr:OK' || echo 'ipv4cidr:FAIL'

# Test generate_hwid (needs WAN MAC)
generate_hwid 2>/dev/null && echo 'hwid:OK' || echo 'hwid:SKIP'

# Test get_device_model
get_device_model 2>/dev/null && echo 'model:OK' || echo 'model:SKIP'

# Test URL parsing
url_get_host 'https://example.com:8080/path' | grep -q 'example.com' && echo 'url-host:OK' || echo 'url-host:FAIL'
url_get_port 'https://example.com:8080/path' | grep -q '8080' && echo 'url-port:OK' || echo 'url-port:FAIL'
url_get_port 'http://[::1]:443/test' | grep -q '443' && echo 'url-ipv6-port:OK' || echo 'url-ipv6-port:FAIL'

echo 'DONE'
TESTEOF

    sed -i "s|HELPERS_PATH|$helpers|" "$tmp"

    sh "$tmp" 2>&1 | while IFS= read -r line; do
        case "$line" in
            *:OK) pass "$line" ;;
            *:FAIL) fail "$line" ;;
            *:SKIP) skip "$line" ;;
            DONE) ;;
            *) ;;
        esac
    done

    rm -f "$tmp"
}

# ─────────────────────────────────────────────────────────────────
# Test: NFT Rules Syntax
# ─────────────────────────────────────────────────────────────────
test_nft() {
    header "NFT Rules Syntax"

    if ! command -v nft > /dev/null 2>&1; then
        skip "nft not available"
        return
    fi

    # Test basic nft operations
    local test_table="netshift_test_$$"
    if nft add table inet "$test_table" 2>/dev/null; then
        pass "nft table creation works"
        nft delete table inet "$test_table" 2>/dev/null
    else
        fail "nft table creation failed (are capabilities set?)"
        return
    fi

    # Test set creation
    if nft add table inet "$test_table" 2>/dev/null && \
       nft add set inet "$test_table" testset '{ type ipv4_addr; flags interval; auto-merge; }' 2>/dev/null && \
       nft add element inet "$test_table" testset '{ 10.0.0.0/8 }' 2>/dev/null; then
        pass "nft set and element operations work"
        nft delete table inet "$test_table" 2>/dev/null
    else
        fail "nft set/element operations failed"
        nft delete table inet "$test_table" 2>/dev/null
    fi

    # Test chain creation
    if nft add table inet "$test_table" 2>/dev/null && \
       nft add chain inet "$test_table" testchain '{ type filter hook input priority 0; policy accept; }' 2>/dev/null; then
        pass "nft chain creation works"
        nft delete table inet "$test_table" 2>/dev/null
    else
        fail "nft chain creation failed"
        nft delete table inet "$test_table" 2>/dev/null
    fi
}

# ─────────────────────────────────────────────────────────────────
# Test: sing-box Config Generation
# ─────────────────────────────────────────────────────────────────
test_sing_box_config() {
    header "sing-box Config Generation"

    if ! command -v sing-box > /dev/null 2>&1; then
        skip "sing-box not installed"
        return
    fi

    # Create a minimal valid sing-box config and validate it
    local test_config="/tmp/test-sing-box-config.json"
    jq -n '{
        log: { disabled: false, level: "warn", timestamp: true },
        dns: { servers: [], rules: [], final: "direct", strategy: "prefer_ipv4", independent_cache: true },
        ntp: {},
        inbounds: [
            { type: "direct", tag: "dns-in", listen: "127.0.0.42", listen_port: 53 }
        ],
        outbounds: [
            { type: "direct", tag: "direct-out" }
        ],
        route: { rules: [], rule_set: [], final: "direct-out", auto_detect_interface: true }
    }' > "$test_config"

    if sing-box -c "$test_config" check > /dev/null 2>&1; then
        pass "sing-box validates minimal config"
    else
        fail "sing-box config validation failed" "$(sing-box -c "$test_config" check 2>&1)"
    fi

    # Test with FakeIP
    jq '.dns.servers += [{
        type: "fakeip", tag: "fakeip", inet4_range: "198.18.0.0/15"
    }]' "$test_config" > "${test_config}.2"

    if sing-box -c "${test_config}.2" check > /dev/null 2>&1; then
        pass "sing-box validates config with FakeIP"
    else
        fail "sing-box FakeIP config failed"
    fi

    # Test with TProxy inbound
    jq '.inbounds += [{
        type: "tproxy", tag: "tproxy-in",
        listen: "127.0.0.1", listen_port: 1602,
        tcp_fast_open: true, udp_fragment: true
    }]' "$test_config" > "${test_config}.3"

    if sing-box -c "${test_config}.3" check > /dev/null 2>&1; then
        pass "sing-box validates config with TProxy"
    else
        fail "sing-box TProxy config failed"
    fi

    # Test with inline ruleset (DoH blocking)
    jq '.route.rule_set += [{
        type: "inline", tag: "doh-block",
        rules: [{ ip_cidr: ["1.1.1.1/32", "8.8.8.8/32"] }]
    }]' "$test_config" > "${test_config}.4"

    if sing-box -c "${test_config}.4" check > /dev/null 2>&1; then
        pass "sing-box validates inline ruleset (DoH block)"
    else
        fail "sing-box inline ruleset failed"
    fi

    # Test with IPv6 fakeip
    jq '.dns.servers[0].inet6_range = "fd00:ec3a::/32"' "${test_config}.2" > "${test_config}.5"

    if sing-box -c "${test_config}.5" check > /dev/null 2>&1; then
        pass "sing-box validates config with IPv6 FakeIP"
    else
        fail "sing-box IPv6 FakeIP failed"
    fi

    rm -f "$test_config" "${test_config}.2" "${test_config}.3" "${test_config}.4" "${test_config}.5"

    # ── VMess vmess://base64(JSON) parse path (facade) ─────────────────────
    # Validate the GENERATED outbound JSON SHAPE with jq (NOT a live sing-box
    # check): the test container's sing-box is the stock build, which rejects
    # the vmess type, so we assert shape only. The extended gate is exercised
    # by toggling is_sing_box_extended via a shell override.
    local facade_lib="${NETSHIFT_LIB_DIR}/sing_box_config_facade.sh"
    if [ ! -r "$facade_lib" ]; then
        fail "sing_box_config_facade.sh not found"
        return
    fi

    # The facade hardcodes NETSHIFT_LIB="/usr/lib/netshift" for its own sourcing
    # of helpers.sh + sing_box_config_manager.sh; bind the bind-mounted sources
    # to that runtime path so the facade resolves them in the container.
    mkdir -p /usr/lib/netshift
    ln -sf "${NETSHIFT_LIB_DIR}/helpers.sh" /usr/lib/netshift/helpers.sh
    ln -sf "${NETSHIFT_LIB_DIR}/sing_box_config_manager.sh" /usr/lib/netshift/sing_box_config_manager.sh

    local vm_tmp="/tmp/test-vmess-facade-$$.sh"
    cat > "$vm_tmp" << 'VMEOF'
# logging.sh is sourced by /usr/bin/netshift in production; the facade itself
# only sources helpers + manager, so pull it in for log() here.
. "NETSHIFT_LIB/logging.sh" 2>/dev/null || log() { :; }
. "FACADE_LIB_PATH"

base_config='{"outbounds":[]}'

# ws + tls synthetic link: base64(JSON). aid=0 must be omitted.
ws_json='{"v":"2","ps":"node-ws","add":"ws.example.com","port":"443","id":"11111111-2222-3333-4444-555555555555","aid":"0","scy":"auto","net":"ws","host":"ws.example.com","path":"/wspath","tls":"tls","sni":"sni.example.com","alpn":"h2,http/1.1","fp":"chrome"}'
ws_link="vmess://$(printf '%s' "$ws_json" | base64 | tr -d '\n')"

# plain tcp synthetic link: no transport, no tls.
tcp_json='{"v":"2","ps":"node-tcp","add":"tcp.example.com","port":"8080","id":"99999999-8888-7777-6666-555555555555","aid":"0","scy":"auto","net":"tcp","host":"","path":"","tls":"","sni":"","alpn":"","fp":""}'
tcp_link="vmess://$(printf '%s' "$tcp_json" | base64 | tr -d '\n')"

# REGRESSION (S1): a key whose STANDARD base64 body DELIBERATELY contains a '+'.
# The "node>>" ps label (bytes 0x3E 0x3E) forces a base64 group that maps to
# '+' (alphabet index 62). If the facade url_decode'd the link before decoding,
# the '+'->space rewrite would corrupt the body and base64 -d would fail/garble,
# so this outbound would NOT be generated. Asserting server/uuid here proves the
# raw-link threading keeps '+' intact.
plus_json='{"v":"2","ps":"node>>","add":"plus.example.com","port":"2053","id":"abcdef00-1111-2222-3333-444455556666","aid":"0","scy":"auto","net":"tcp","host":"","path":"","tls":"","sni":"","alpn":"","fp":""}'
plus_link="vmess://$(printf '%s' "$plus_json" | base64 | tr -d '\n')"
# Sanity: confirm the crafted base64 body actually contains a '+'.
case "$plus_link" in
*+*) echo 'vmess-plus-body-has-plus:OK' ;;
*) echo 'vmess-plus-body-has-plus:FAIL' ;;
esac

# ── Extended ON: parse path produces a real vmess outbound ──
is_sing_box_extended() { return 0; }

out_ws=$(sing_box_cf_add_proxy_outbound "$base_config" "vmess_ws" "$ws_link" "0")
echo "$out_ws" | jq -e '.outbounds[0].type == "vmess"' >/dev/null 2>&1 && echo 'vmess-ws-type:OK' || echo 'vmess-ws-type:FAIL'
echo "$out_ws" | jq -e '.outbounds[0].server == "ws.example.com"' >/dev/null 2>&1 && echo 'vmess-ws-server:OK' || echo 'vmess-ws-server:FAIL'
echo "$out_ws" | jq -e '.outbounds[0].server_port == 443' >/dev/null 2>&1 && echo 'vmess-ws-port:OK' || echo 'vmess-ws-port:FAIL'
echo "$out_ws" | jq -e '.outbounds[0] | has("alter_id") | not' >/dev/null 2>&1 && echo 'vmess-ws-aid-omitted:OK' || echo 'vmess-ws-aid-omitted:FAIL'
echo "$out_ws" | jq -e '.outbounds[0].transport.type == "ws"' >/dev/null 2>&1 && echo 'vmess-ws-transport:OK' || echo 'vmess-ws-transport:FAIL'
echo "$out_ws" | jq -e '.outbounds[0].transport.path == "/wspath"' >/dev/null 2>&1 && echo 'vmess-ws-path:OK' || echo 'vmess-ws-path:FAIL'
echo "$out_ws" | jq -e '.outbounds[0].transport.headers.Host == "ws.example.com"' >/dev/null 2>&1 && echo 'vmess-ws-host:OK' || echo 'vmess-ws-host:FAIL'
echo "$out_ws" | jq -e '.outbounds[0].tls.enabled == true' >/dev/null 2>&1 && echo 'vmess-ws-tls:OK' || echo 'vmess-ws-tls:FAIL'
echo "$out_ws" | jq -e '.outbounds[0].tls.server_name == "sni.example.com"' >/dev/null 2>&1 && echo 'vmess-ws-sni:OK' || echo 'vmess-ws-sni:FAIL'
echo "$out_ws" | jq -e '.outbounds[0].tls.alpn == ["h2","http/1.1"]' >/dev/null 2>&1 && echo 'vmess-ws-alpn:OK' || echo 'vmess-ws-alpn:FAIL'
echo "$out_ws" | jq -e '.outbounds[0].tls.utls.fingerprint == "chrome"' >/dev/null 2>&1 && echo 'vmess-ws-fp:OK' || echo 'vmess-ws-fp:FAIL'

out_tcp=$(sing_box_cf_add_proxy_outbound "$base_config" "vmess_tcp" "$tcp_link" "0")
echo "$out_tcp" | jq -e '.outbounds[0].type == "vmess"' >/dev/null 2>&1 && echo 'vmess-tcp-type:OK' || echo 'vmess-tcp-type:FAIL'
echo "$out_tcp" | jq -e '.outbounds[0] | has("transport") | not' >/dev/null 2>&1 && echo 'vmess-tcp-no-transport:OK' || echo 'vmess-tcp-no-transport:FAIL'
echo "$out_tcp" | jq -e '.outbounds[0] | has("tls") | not' >/dev/null 2>&1 && echo 'vmess-tcp-no-tls:OK' || echo 'vmess-tcp-no-tls:FAIL'
echo "$out_tcp" | jq -e '.outbounds[0].security == "auto"' >/dev/null 2>&1 && echo 'vmess-tcp-security:OK' || echo 'vmess-tcp-security:FAIL'

# ── REGRESSION (S1): '+'-in-base64 link must parse via the RAW link ──
out_plus=$(sing_box_cf_add_proxy_outbound "$base_config" "vmess_plus" "$plus_link" "0")
echo "$out_plus" | jq -e '.outbounds[0].type == "vmess"' >/dev/null 2>&1 && echo 'vmess-plus-type:OK' || echo 'vmess-plus-type:FAIL'
echo "$out_plus" | jq -e '.outbounds[0].server == "plus.example.com"' >/dev/null 2>&1 && echo 'vmess-plus-server:OK' || echo 'vmess-plus-server:FAIL'
echo "$out_plus" | jq -e '.outbounds[0].server_port == 2053' >/dev/null 2>&1 && echo 'vmess-plus-port:OK' || echo 'vmess-plus-port:FAIL'
echo "$out_plus" | jq -e '.outbounds[0].uuid == "abcdef00-1111-2222-3333-444455556666"' >/dev/null 2>&1 && echo 'vmess-plus-uuid:OK' || echo 'vmess-plus-uuid:FAIL'

# ── Extended OFF: gate returns config UNCHANGED (no vmess outbound) ──
is_sing_box_extended() { return 1; }
out_gate=$(sing_box_cf_add_proxy_outbound "$base_config" "vmess_gate" "$ws_link" "0")
echo "$out_gate" | jq -e '.outbounds | length == 0' >/dev/null 2>&1 && echo 'vmess-gate-unchanged:OK' || echo 'vmess-gate-unchanged:FAIL'

echo 'DONE'
VMEOF
    sed -i "s|FACADE_LIB_PATH|$facade_lib|; s|NETSHIFT_LIB|$NETSHIFT_LIB_DIR|g" "$vm_tmp"

    sh "$vm_tmp" 2>&1 | while IFS= read -r line; do
        case "$line" in
            *:OK) pass "$line" ;;
            *:FAIL) fail "$line" ;;
            *:SKIP) skip "$line" ;;
            DONE) ;;
            *) ;;
        esac
    done
    rm -f "$vm_tmp"
}

# ─────────────────────────────────────────────────────────────────
# Test: Diagnostics Commands
# ─────────────────────────────────────────────────────────────────
test_diagnostics() {
    header "Diagnostics Commands"

    if ! command -v sing-box > /dev/null 2>&1; then
        skip "sing-box not installed — skipping diagnostic tests"
        return
    fi

    # sing-box version
    if sing-box version > /dev/null 2>&1; then
        pass "sing-box version works"
    else
        fail "sing-box version failed"
    fi

    # sing-box check on empty config
    echo '{}' > /tmp/empty.json
    if sing-box -c /tmp/empty.json check > /dev/null 2>&1; then
        pass "sing-box check accepts empty config"
    else
        # This might fail — some versions require more structure
        pass "sing-box check rejects empty config (expected on newer versions)"
    fi
    rm -f /tmp/empty.json

    # dig
    if command -v dig > /dev/null 2>&1; then
        if dig +short +timeout=3 google.com > /dev/null 2>&1; then
            pass "dig DNS resolution works"
        else
            skip "dig DNS resolution (no network?)"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────
# Test: jq Helpers
# ─────────────────────────────────────────────────────────────────
test_jq_helpers() {
    header "jq Helper Functions"

    local jq_helpers="${NETSHIFT_LIB_DIR}/helpers.jq"

    if [ ! -r "$jq_helpers" ]; then
        skip "helpers.jq not found"
        return
    fi

    # Production scripts import helpers.jq from /usr/lib/netshift. In the test
    # container sources are bind-mounted under /netshift/files, so provide the
    # runtime path as a symlink for jq module resolution.
    mkdir -p /usr/lib/netshift
    ln -sf "$jq_helpers" /usr/lib/netshift/helpers.jq

    # Test the extend_key_value function. Keep the jq program in a file instead
    # of a shell variable because BusyBox ash can choke on jq syntax like
    # `h::extend_key_value(.; ...)` during script parsing in some builds.
    local jq_filter_file="/tmp/netshift-jq-filter-$$.jq"
    cat > "$jq_filter_file" << 'JQEOF'
import "helpers" as h;
[1,2,3] | h::extend_key_value(.; [4,5])
JQEOF
    local jq_error_file="/tmp/netshift-jq-error-$$.log"
    result=$(jq -n -L "/usr/lib/netshift" -f "$jq_filter_file" 2>"$jq_error_file" || true)
    rm -f "$jq_filter_file"
    
    if echo "$result" | jq -e '. | length == 5' > /dev/null 2>&1; then
        pass "helpers.jq extend_key_value merges arrays"
    else
        fail "helpers.jq extend_key_value failed" "got: $result $(cat "$jq_error_file" 2>/dev/null)"
    fi
    rm -f "$jq_error_file"
}

# ─────────────────────────────────────────────────────────────────
# Test: Config Manager JSON Generation
# ─────────────────────────────────────────────────────────────────
test_config_manager() {
    header "sing-box Config Manager (jq)"

    if ! command -v jq > /dev/null 2>&1; then
        skip "jq not available"
        return
    fi

    # Test basic config operations by simulating the config manager pipeline
    local config
    config=$(jq -n '{
        log: {}, dns: {}, ntp: {}, certificate: {}, endpoints: [],
        inbounds: [], outbounds: [], route: {}, services: [], experimental: {}
    }')

    # Simulate adding a direct outbound
    config=$(echo "$config" | jq '.outbounds += [{ type: "direct", tag: "direct-out" }]')
    if echo "$config" | jq -e '.outbounds | length == 1' > /dev/null 2>&1; then
        pass "jq: direct outbound added to config"
    else
        fail "jq: direct outbound failed"
    fi

    # Simulate adding a TProxy inbound
    config=$(echo "$config" | jq '.inbounds += [{
        type: "tproxy", tag: "tproxy-in",
        listen: "127.0.0.1", listen_port: 1602,
        tcp_fast_open: true, udp_fragment: true
    }]')
    if echo "$config" | jq -e '.inbounds | length == 1' > /dev/null 2>&1; then
        pass "jq: TProxy inbound added to config"
    else
        fail "jq: TProxy inbound failed"
    fi

    # Simulate adding route rule
    config=$(echo "$config" | jq '.route.rules += [{
        action: "route", inbound: "tproxy-in", outbound: "direct-out"
    }]')
    if echo "$config" | jq -e '.route.rules | length == 1' > /dev/null 2>&1; then
        pass "jq: route rule added to config"
    else
        fail "jq: route rule failed"
    fi

    # ── VMess outbound primitive (sing_box_cm_add_vmess_outbound) ──────────
    local cm_lib="${NETSHIFT_LIB_DIR}/sing_box_config_manager.sh"
    if [ ! -r "$cm_lib" ]; then
        fail "sing_box_config_manager.sh not found"
        return
    fi

    local cm_tmp="/tmp/test-cm-vmess-$$.sh"
    cat > "$cm_tmp" << 'CMEOF'
. "CM_LIB_PATH"

base_config='{"outbounds":[]}'

# Default security ("auto") + alter_id omitted when "0".
out=$(sing_box_cm_add_vmess_outbound "$base_config" "vmess-out" "example.com" "443" \
    "bf000d23-0752-40b4-affe-68f7707a9661" "" "0")
echo "$out" | jq -e '.outbounds[0].type == "vmess"' >/dev/null 2>&1 && echo 'cm-vmess-type:OK' || echo 'cm-vmess-type:FAIL'
echo "$out" | jq -e '.outbounds[0].server == "example.com"' >/dev/null 2>&1 && echo 'cm-vmess-server:OK' || echo 'cm-vmess-server:FAIL'
echo "$out" | jq -e '.outbounds[0].server_port == 443' >/dev/null 2>&1 && echo 'cm-vmess-port:OK' || echo 'cm-vmess-port:FAIL'
echo "$out" | jq -e '.outbounds[0].uuid == "bf000d23-0752-40b4-affe-68f7707a9661"' >/dev/null 2>&1 && echo 'cm-vmess-uuid:OK' || echo 'cm-vmess-uuid:FAIL'
echo "$out" | jq -e '.outbounds[0].security == "auto"' >/dev/null 2>&1 && echo 'cm-vmess-security-default:OK' || echo 'cm-vmess-security-default:FAIL'
echo "$out" | jq -e '.outbounds[0] | has("alter_id") | not' >/dev/null 2>&1 && echo 'cm-vmess-aid-omitted:OK' || echo 'cm-vmess-aid-omitted:FAIL'

# Explicit security + non-zero alter_id present as a number.
out2=$(sing_box_cm_add_vmess_outbound "$base_config" "vmess-out" "example.com" "443" \
    "bf000d23-0752-40b4-affe-68f7707a9661" "aes-128-gcm" "64")
echo "$out2" | jq -e '.outbounds[0].security == "aes-128-gcm"' >/dev/null 2>&1 && echo 'cm-vmess-security-explicit:OK' || echo 'cm-vmess-security-explicit:FAIL'
echo "$out2" | jq -e '.outbounds[0].alter_id == 64' >/dev/null 2>&1 && echo 'cm-vmess-aid-number:OK' || echo 'cm-vmess-aid-number:FAIL'

echo 'DONE'
CMEOF
    sed -i "s|CM_LIB_PATH|$cm_lib|" "$cm_tmp"

    sh "$cm_tmp" 2>&1 | while IFS= read -r line; do
        case "$line" in
            *:OK) pass "$line" ;;
            *:FAIL) fail "$line" ;;
            *:SKIP) skip "$line" ;;
            DONE) ;;
            *) ;;
        esac
    done
    rm -f "$cm_tmp"
}

# ─────────────────────────────────────────────────────────────────
# Test: Subscription JSON Validation
# ─────────────────────────────────────────────────────────────────
test_subscription() {
    header "Subscription JSON Validation"

    if ! command -v jq > /dev/null 2>&1; then
        skip "jq not available"
        return
    fi

    # Create a valid subscription-like JSON
    local sub='{
        "outbounds": [
            {"type": "shadowsocks", "tag": "ss-01", "server": "example.com", "server_port": 443, "method": "aes-256-gcm", "password": "test"},
            {"type": "vless", "tag": "vl-01", "server": "vless.example.com", "server_port": 443, "uuid": "00000000-0000-0000-0000-000000000000", "flow": "xtls-rprx-vision", "tls": {"enabled": true, "server_name": "example.com"}},
            {"type": "trojan", "tag": "tj-01", "server": "trojan.example.com", "server_port": 443, "password": "test"},
            {"type": "hysteria2", "tag": "hy2-01", "server": "hysteria.example.com", "server_port": 443, "password": "test"},
            {"type": "selector", "tag": "select", "outbounds": ["ss-01", "vl-01"]},
            {"type": "urltest", "tag": "auto", "outbounds": ["ss-01", "vl-01"]},
            {"type": "direct", "tag": "direct"},
            {"type": "dns", "tag": "dns"},
            {"type": "block", "tag": "block"}
        ]
    }'

    # Count proxy outbounds (exclude selector, urltest, direct, dns, block)
    local proxy_count
    local proxy_filter_file="/tmp/netshift-proxy-filter-$$.jq"
    cat > "$proxy_filter_file" << 'JQEOF'
[.outbounds[] | select(.type != "selector" and .type != "urltest" and .type != "direct" and .type != "dns" and .type != "block")] | length
JQEOF
    proxy_count=$(echo "$sub" | jq -f "$proxy_filter_file")
    rm -f "$proxy_filter_file"

    if [ "$proxy_count" -eq 4 ]; then
        pass "Subscription proxy count correct: $proxy_count (ss + vless + trojan + hysteria2)"
    else
        fail "Subscription proxy count wrong: expected 4, got $proxy_count"
    fi

    # Test filtering for subscription outbound tags
    local outbound_tags
    local tags_filter_file="/tmp/netshift-tags-filter-$$.jq"
    cat > "$tags_filter_file" << 'JQEOF'
[.outbounds[] | select(.type != "selector" and .type != "urltest" and .type != "direct" and .type != "dns" and .type != "block") | .tag]
JQEOF
    outbound_tags=$(echo "$sub" | jq -c -f "$tags_filter_file")
    rm -f "$tags_filter_file"

    if echo "$outbound_tags" | jq -e 'length == 4' > /dev/null 2>&1; then
        pass "Subscription outbound tags extracted correctly"
    else
        fail "Subscription outbound tags extraction failed"
    fi

    # Test country flag extraction from tags
    # Build tags with actual Unicode regional indicator flags
    local country_test
    local flag_filter_file="/tmp/netshift-flag-filter-$$.jq"
    cat > "$flag_filter_file" << 'JQEOF'
def flag($l1; $l2): ([127462 + $l1, 127462 + $l2] | implode);
[(flag(3; 4) + " Frankfurt"), (flag(20; 18) + " New York"), (flag(13; 11) + " Amsterdam"), (flag(9; 15) + " Tokyo"), "no-flag"]
JQEOF
    country_test=$(jq -cn -f "$flag_filter_file")
    rm -f "$flag_filter_file"

    local grouping
    local group_filter_file="/tmp/netshift-group-filter-$$.jq"
    cat > "$group_filter_file" << 'JQEOF'
def is_regional_indicator: . >= 127462 and . <= 127487;
def extract_country_flag:
  (. | explode) as $codepoints
  | if ($codepoints | length) >= 2
      and ($codepoints[0] | is_regional_indicator)
      and ($codepoints[1] | is_regional_indicator)
    then ($codepoints[0:2] | implode)
    else "" end;
(if type == "array" then . else [] end) as $tags
| reduce $tags[] as $tag (
    {count: 0, ungrouped: 0};
    ($tag | extract_country_flag) as $flag
    | if $flag == "" then .ungrouped += 1 else .count += 1 end
  )
JQEOF
    grouping=$(echo "$country_test" | jq -c -f "$group_filter_file")
    rm -f "$group_filter_file"

    local grouped
    grouped=$(echo "$grouping" | jq -r '.count')
    local ungrouped
    ungrouped=$(echo "$grouping" | jq -r '.ungrouped')

    if [ "$grouped" -eq 4 ] && [ "$ungrouped" -eq 1 ]; then
        pass "Country flag grouping: $grouped grouped, $ungrouped ungrouped"
    else
        fail "Country flag grouping wrong: got $grouped grouped, $ungrouped ungrouped"
    fi

    # ── Fallback Subscription Normalizer (helpers.sh) ───────────────
    # Exercise normalize_subscription_to_singbox end-to-end against the
    # real libs. The facade hardcodes NETSHIFT_LIB=/usr/lib/netshift, so we
    # mirror test_jq_helpers and expose the bind-mounted libs there via
    # symlinks, then source constants + logging + facade (the facade pulls in
    # helpers.sh and the config manager). Tokens are emitted on stdout and
    # parsed with the same name:OK/FAIL/SKIP convention used by test_helpers.
    # NB: no `set -u` in the harness — the URI builders rely on optional unset
    # query-param vars, exactly like the production backend.
    printf "\n  ${BOLD}Fallback Subscription Normalizer${NC}\n"

    local lib="${NETSHIFT_LIB_DIR}"
    if [ ! -r "$lib/helpers.sh" ] || [ ! -r "$lib/sing_box_config_facade.sh" ]; then
        skip "fallback normalizer (libs not found in $lib)"
        return
    fi

    local fb="/tmp/netshift-sub-fallback-$$.sh"
    cat > "$fb" << 'FBEOF'
# Make the facade's hardcoded NETSHIFT_LIB path resolve to the bind-mounted libs.
mkdir -p /usr/lib/netshift
for f in constants.sh helpers.sh logging.sh sing_box_config_manager.sh sing_box_config_facade.sh; do
    ln -sf "LIB_DIR/$f" "/usr/lib/netshift/$f"
done

. /usr/lib/netshift/constants.sh
. /usr/lib/netshift/logging.sh
# The facade sources helpers.sh + sing_box_config_manager.sh itself.
. /usr/lib/netshift/sing_box_config_facade.sh

# ── CASE A: plaintext URI list with comment/metadata lines ──────────
caseA_in="/tmp/netshift-fb-caseA-$$.txt"
caseA_out="/tmp/netshift-fb-caseA-out-$$.json"
cat > "$caseA_in" << 'LIST'
#profile-title: Test
#subscription-userinfo: upload=0
vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&sni=example.com&type=tcp#A
trojan://password123@example.com:8443?security=tls&sni=example.com#B
ss://YWVzLTI1Ni1nY206cGFzcw==@example.com:8388#C
hysteria2://pass@example.com:443?sni=example.com#D

socks5://user:pass@example.com:1080#E
LIST

if normalize_subscription_to_singbox "$caseA_in" "$caseA_out" "testsub"; then
    echo 'fb-caseA-rc:OK'
else
    echo 'fb-caseA-rc:FAIL'
fi
a_len="$(jq -r '.outbounds | length' "$caseA_out" 2>/dev/null)"
[ -n "$a_len" ] || a_len=0
if [ "$a_len" -ge 4 ]; then
    echo "fb-caseA-count(>=4 got $a_len):OK"
else
    echo "fb-caseA-count(>=4 got $a_len):FAIL"
fi
if validate_subscription_file "$caseA_out"; then
    echo 'fb-caseA-validate:OK'
else
    echo 'fb-caseA-validate:FAIL'
fi
rm -f "$caseA_in" "$caseA_out"

# ── CASE B: base64-wrapped URI list ─────────────────────────────────
# busybox base64 may lack -w0; encode then strip newlines with tr.
caseB_plain="vless://22222222-2222-2222-2222-222222222222@example.com:443?security=tls&sni=example.com&type=tcp#B1
trojan://secretpw@example.com:8443?security=tls&sni=example.com#B2"
caseB_in="/tmp/netshift-fb-caseB-$$.txt"
caseB_out="/tmp/netshift-fb-caseB-out-$$.json"
printf '%s' "$caseB_plain" | base64 | tr -d '\n' > "$caseB_in"

if normalize_subscription_to_singbox "$caseB_in" "$caseB_out" "testsub"; then
    echo 'fb-caseB-rc:OK'
else
    echo 'fb-caseB-rc:FAIL'
fi
b_len="$(jq -r '.outbounds | length' "$caseB_out" 2>/dev/null)"
[ -n "$b_len" ] || b_len=0
if [ "$b_len" -ge 2 ]; then
    echo "fb-caseB-count(>=2 got $b_len):OK"
else
    echo "fb-caseB-count(>=2 got $b_len):FAIL"
fi
if validate_subscription_file "$caseB_out"; then
    echo 'fb-caseB-validate:OK'
else
    echo 'fb-caseB-validate:FAIL'
fi
rm -f "$caseB_in" "$caseB_out"

# ── CASE C: robustness — valid keys mixed with garbage ──────────────
# Two valid known-scheme keys; an unknown scheme (vmess), a malformed line,
# a blank line and a comment must all be skipped without aborting the parse.
caseC_in="/tmp/netshift-fb-caseC-$$.txt"
caseC_out="/tmp/netshift-fb-caseC-out-$$.json"
cat > "$caseC_in" << 'LIST'
#header comment
vless://33333333-3333-3333-3333-333333333333@example.com:443?security=tls&sni=example.com&type=tcp#C1
vmess://eyJ0aGlzIjoidW5rbm93biJ9
not-a-uri

trojan://pw3@example.com:8443?security=tls&sni=example.com#C2
LIST

if normalize_subscription_to_singbox "$caseC_in" "$caseC_out" "testsub"; then
    echo 'fb-caseC-rc:OK'
else
    echo 'fb-caseC-rc:FAIL'
fi
c_len="$(jq -r '.outbounds | length' "$caseC_out" 2>/dev/null)"
[ -n "$c_len" ] || c_len=0
if [ "$c_len" -eq 2 ]; then
    echo "fb-caseC-count(==2 valid got $c_len):OK"
else
    echo "fb-caseC-count(==2 valid got $c_len):FAIL"
fi
rm -f "$caseC_in" "$caseC_out"

# ── CASE D: negative — only comments / junk, no valid keys ──────────
caseD_in="/tmp/netshift-fb-caseD-$$.txt"
caseD_out="/tmp/netshift-fb-caseD-out-$$.json"
cat > "$caseD_in" << 'LIST'
#profile-title: Empty
#subscription-userinfo: upload=0
not-a-uri
vmess://eyJqdW5rIjoidHJ1ZSJ9

LIST

if normalize_subscription_to_singbox "$caseD_in" "$caseD_out" "testsub"; then
    echo 'fb-caseD-rc-nonzero:FAIL'
else
    echo 'fb-caseD-rc-nonzero:OK'
fi
# No usable output: either no file, or a file that fails validation.
if [ ! -s "$caseD_out" ] || ! validate_subscription_file "$caseD_out"; then
    echo 'fb-caseD-no-usable-output:OK'
else
    echo 'fb-caseD-no-usable-output:FAIL'
fi
rm -f "$caseD_in" "$caseD_out"

# ── CASE E: Xray JSON subscription (array of Xray client configs) ───
# A provider that returns an "Xray JSON" body instead of a sing-box config:
# an array of Xray configs whose proxy outbounds use the Xray schema
# (protocol + settings.vnext + streamSettings). The normalizer must detect
# this, convert the directly-usable (non-dialerProxy) outbounds to share URIs
# and produce a valid sing-box config. The chained (sockopt.dialerProxy)
# outbound must be skipped.
caseE_in="/tmp/netshift-fb-caseE-$$.json"
caseE_out="/tmp/netshift-fb-caseE-out-$$.json"
cat > "$caseE_in" << 'XRAYJSON'
[
  {
    "remarks": "Reality TCP",
    "outbounds": [
      {
        "protocol": "vless",
        "tag": "proxy-reality",
        "settings": {"vnext": [{"address": "uk.example.com", "port": 8443,
          "users": [{"id": "59e308c0-071d-4214-bb4a-64a2409d9e3b",
            "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
        "streamSettings": {"network": "tcp", "security": "reality",
          "realitySettings": {"publicKey": "dY9SNEllJMW63xo-JdXufhmjAxB",
            "shortId": "c20b1035d72d7793", "serverName": "storage.yandex.net",
            "fingerprint": "firefox"}}
      }
    ]
  },
  {
    "remarks": "WS TLS",
    "outbounds": [
      {
        "protocol": "vless",
        "tag": "proxy-ws",
        "settings": {"vnext": [{"address": "ws.example.com", "port": 443,
          "users": [{"id": "dea6c6da-3903-4dbc-b98c-e79364764f9f",
            "flow": "", "encryption": "none"}]}]},
        "streamSettings": {"network": "ws", "security": "tls",
          "tlsSettings": {"serverName": "ws.example.com"},
          "wsSettings": {"path": "/livestreamcontent/",
            "headers": {"Host": "ws.example.com"}}}
      },
      {
        "protocol": "vless",
        "tag": "proxy-chained",
        "settings": {"vnext": [{"address": "bypass.example.com", "port": 8443,
          "users": [{"id": "8c459cd3-f3b0-496c-9d87-138d292ecdf6",
            "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
        "streamSettings": {"network": "tcp", "security": "reality",
          "sockopt": {"dialerProxy": "upstream-0"},
          "realitySettings": {"publicKey": "abc", "shortId": "def",
            "serverName": "storage.yandex.net", "fingerprint": "firefox"}}
      }
    ]
  }
]
XRAYJSON

if normalize_subscription_to_singbox "$caseE_in" "$caseE_out" "testsub"; then
    echo 'fb-caseE-rc:OK'
else
    echo 'fb-caseE-rc:FAIL'
fi
# Exactly two usable outbounds: reality-tcp + ws-tls; the dialerProxy one skipped.
e_len="$(jq -r '.outbounds | length' "$caseE_out" 2>/dev/null)"
[ -n "$e_len" ] || e_len=0
if [ "$e_len" -eq 2 ]; then
    echo "fb-caseE-count(==2 got $e_len):OK"
else
    echo "fb-caseE-count(==2 got $e_len):FAIL"
fi
if validate_subscription_file "$caseE_out"; then
    echo 'fb-caseE-validate:OK'
else
    echo 'fb-caseE-validate:FAIL'
fi
# The reality outbound must carry the converted reality block + flow.
if jq -e '[.outbounds[] | select(.type == "vless"
        and .tls.reality.public_key == "dY9SNEllJMW63xo-JdXufhmjAxB"
        and .flow == "xtls-rprx-vision")] | length == 1' "$caseE_out" \
        > /dev/null 2>&1; then
    echo 'fb-caseE-reality-fields:OK'
else
    echo 'fb-caseE-reality-fields:FAIL'
fi
rm -f "$caseE_in" "$caseE_out"

# ── CASE F: Xray JSON reality node WITHOUT shortId ──────────────────
# Regression guard: a missing Xray field reads as JSON null, and a naive
# (null | tostring) would emit a literal "sid=null" query param, which
# sing-box would then store as short_id:"null". The converter must drop the
# absent param entirely, so the produced reality block carries NO short_id.
caseF_in="/tmp/netshift-fb-caseF-$$.json"
caseF_out="/tmp/netshift-fb-caseF-out-$$.json"
cat > "$caseF_in" << 'XRAYJSON'
[
  {
    "remarks": "no-sid",
    "outbounds": [
      {
        "protocol": "vless",
        "tag": "proxy-no-sid",
        "settings": {"vnext": [{"address": "ru.example.com", "port": 443,
          "users": [{"id": "1dff23f6-b2f1-4242-9746-b586808ed302",
            "encryption": "none"}]}]},
        "streamSettings": {"network": "tcp", "security": "reality",
          "realitySettings": {"publicKey": "G2i-nsQgWiVf52tdCUV",
            "serverName": "cloudrynth.com", "fingerprint": "firefox"}}
      }
    ]
  }
]
XRAYJSON

if normalize_subscription_to_singbox "$caseF_in" "$caseF_out" "testsub"; then
    echo 'fb-caseF-rc:OK'
else
    echo 'fb-caseF-rc:FAIL'
fi
if validate_subscription_file "$caseF_out"; then
    echo 'fb-caseF-validate:OK'
else
    echo 'fb-caseF-validate:FAIL'
fi
# No outbound may carry a literal "null" short_id, and the public_key must be set.
if jq -e '([.outbounds[].tls.reality.short_id // empty] | map(select(. == "null")) | length) == 0
        and ([.outbounds[] | select(.tls.reality.public_key == "G2i-nsQgWiVf52tdCUV")] | length == 1)' \
        "$caseF_out" > /dev/null 2>&1; then
    echo 'fb-caseF-no-null-sid:OK'
else
    echo 'fb-caseF-no-null-sid:FAIL'
fi
rm -f "$caseF_in" "$caseF_out"

# ── CASE G: Xray JSON duplicate-node dedup ──────────────────────────
# Providers commonly ship one server set across many "profiles"/balancers,
# repeating identical nodes with only the display name differing. The
# converter must dedup on the connection part (ignoring the #name), so N
# copies of the same server collapse to one. Here three configs reference the
# same two servers (A, B) plus one extra (C) -> exactly 3 unique outbounds.
caseG_in="/tmp/netshift-fb-caseG-$$.json"
caseG_out="/tmp/netshift-fb-caseG-out-$$.json"
cat > "$caseG_in" << 'XRAYJSON'
[
  {"remarks": "profile-1", "outbounds": [
    {"protocol": "vless", "tag": "A", "settings": {"vnext": [{"address": "a.example.com", "port": 443,
      "users": [{"id": "11111111-1111-1111-1111-111111111111", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
      "streamSettings": {"network": "tcp", "security": "reality",
        "realitySettings": {"publicKey": "PK", "shortId": "ab", "serverName": "a.example.com", "fingerprint": "firefox"}}},
    {"protocol": "vless", "tag": "B", "settings": {"vnext": [{"address": "b.example.com", "port": 443,
      "users": [{"id": "22222222-2222-2222-2222-222222222222", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
      "streamSettings": {"network": "tcp", "security": "reality",
        "realitySettings": {"publicKey": "PK", "shortId": "cd", "serverName": "b.example.com", "fingerprint": "firefox"}}}
  ]},
  {"remarks": "profile-2", "outbounds": [
    {"protocol": "vless", "tag": "A-copy", "settings": {"vnext": [{"address": "a.example.com", "port": 443,
      "users": [{"id": "11111111-1111-1111-1111-111111111111", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
      "streamSettings": {"network": "tcp", "security": "reality",
        "realitySettings": {"publicKey": "PK", "shortId": "ab", "serverName": "a.example.com", "fingerprint": "firefox"}}},
    {"protocol": "vless", "tag": "B-copy", "settings": {"vnext": [{"address": "b.example.com", "port": 443,
      "users": [{"id": "22222222-2222-2222-2222-222222222222", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
      "streamSettings": {"network": "tcp", "security": "reality",
        "realitySettings": {"publicKey": "PK", "shortId": "cd", "serverName": "b.example.com", "fingerprint": "firefox"}}}
  ]},
  {"remarks": "profile-3", "outbounds": [
    {"protocol": "vless", "tag": "C", "settings": {"vnext": [{"address": "c.example.com", "port": 443,
      "users": [{"id": "33333333-3333-3333-3333-333333333333", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
      "streamSettings": {"network": "tcp", "security": "reality",
        "realitySettings": {"publicKey": "PK", "shortId": "ef", "serverName": "c.example.com", "fingerprint": "firefox"}}}
  ]}
]
XRAYJSON

if normalize_subscription_to_singbox "$caseG_in" "$caseG_out" "testsub"; then
    echo 'fb-caseG-rc:OK'
else
    echo 'fb-caseG-rc:FAIL'
fi
# 5 raw nodes (A,B,A-copy,B-copy,C) must dedup to 3 unique servers (A,B,C).
g_len="$(jq -r '.outbounds | length' "$caseG_out" 2>/dev/null)"
[ -n "$g_len" ] || g_len=0
if [ "$g_len" -eq 3 ]; then
    echo "fb-caseG-dedup(==3 got $g_len):OK"
else
    echo "fb-caseG-dedup(==3 got $g_len):FAIL"
fi
# All three distinct servers must survive (a, b, c).
if jq -e '([.outbounds[].server] | sort) == ["a.example.com","b.example.com","c.example.com"]' \
        "$caseG_out" > /dev/null 2>&1; then
    echo 'fb-caseG-servers:OK'
else
    echo 'fb-caseG-servers:FAIL'
fi
rm -f "$caseG_in" "$caseG_out"

# ── CASE H: Xray JSON with unsupported VMess alongside VLESS ────────
# The facade cannot build VMess. The converter must skip vmess but keep the
# vless node, and xray_json_count_unsupported must report the dropped vmess so
# the backend can warn the user instead of silently losing it.
caseH_in="/tmp/netshift-fb-caseH-$$.json"
caseH_out="/tmp/netshift-fb-caseH-out-$$.json"
cat > "$caseH_in" << 'XRAYJSON'
[
  {
    "remarks": "mixed",
    "outbounds": [
      {
        "protocol": "vless",
        "tag": "ok-vless",
        "settings": {"vnext": [{"address": "vl.example.com", "port": 443,
          "users": [{"id": "11111111-1111-1111-1111-111111111111",
            "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
        "streamSettings": {"network": "tcp", "security": "reality",
          "realitySettings": {"publicKey": "PK", "shortId": "ab",
            "serverName": "vl.example.com", "fingerprint": "firefox"}}
      },
      {
        "protocol": "vmess",
        "tag": "drop-vmess",
        "settings": {"vnext": [{"address": "vm.example.com", "port": 443,
          "users": [{"id": "22222222-2222-2222-2222-222222222222",
            "alterId": 0, "security": "auto"}]}]},
        "streamSettings": {"network": "tcp", "security": "tls",
          "tlsSettings": {"serverName": "vm.example.com"}}
      }
    ]
  }
]
XRAYJSON

if normalize_subscription_to_singbox "$caseH_in" "$caseH_out" "testsub"; then
    echo 'fb-caseH-rc:OK'
else
    echo 'fb-caseH-rc:FAIL'
fi
# Exactly one usable outbound (vless); vmess dropped.
h_len="$(jq -r '.outbounds | length' "$caseH_out" 2>/dev/null)"
[ -n "$h_len" ] || h_len=0
if [ "$h_len" -eq 1 ] \
        && jq -e '.outbounds[0].server == "vl.example.com"' "$caseH_out" >/dev/null 2>&1; then
    echo "fb-caseH-vless-kept(==1 got $h_len):OK"
else
    echo "fb-caseH-vless-kept(==1 got $h_len):FAIL"
fi
# The unsupported-protocol counter must report exactly one vmess.
h_unsup="$(xray_json_count_unsupported "$caseH_in")"
if [ "$h_unsup" = "1" ]; then
    echo 'fb-caseH-vmess-counted:OK'
else
    echo "fb-caseH-vmess-counted(==1 got $h_unsup):FAIL"
fi
rm -f "$caseH_in" "$caseH_out"

# ── CASE I: subscription User-Agent candidate building ──────────────
# Auto mode (no configured UA) must emit, in order and without duplicates:
# the default singbox/<ver> first, then the cached/preferred UA, then the
# constants whitelist. A configured UA must short-circuit to exactly itself.
caseI_default="$(get_subscription_user_agent)"

# (a) Auto mode, no preferred: first line is the default; v2rayN present; no dup default.
caseI_auto="$(build_subscription_user_agent_candidates "" "")"
caseI_first="$(printf '%s\n' "$caseI_auto" | sed -n '1p')"
if [ "$caseI_first" = "$caseI_default" ]; then
    echo 'fb-caseI-auto-default-first:OK'
else
    echo "fb-caseI-auto-default-first(got '$caseI_first'):FAIL"
fi
if printf '%s\n' "$caseI_auto" | grep -Fxq 'v2rayN'; then
    echo 'fb-caseI-auto-has-v2rayN:OK'
else
    echo 'fb-caseI-auto-has-v2rayN:FAIL'
fi
caseI_default_count="$(printf '%s\n' "$caseI_auto" | grep -Fxc "$caseI_default")"
if [ "$caseI_default_count" = "1" ]; then
    echo 'fb-caseI-auto-default-unique:OK'
else
    echo "fb-caseI-auto-default-unique(got $caseI_default_count):FAIL"
fi

# (b) Preferred UA is emitted right after the default and only once.
caseI_pref="$(build_subscription_user_agent_candidates "" "Hiddify")"
caseI_second="$(printf '%s\n' "$caseI_pref" | sed -n '2p')"
caseI_hid_count="$(printf '%s\n' "$caseI_pref" | grep -Fxc 'Hiddify')"
if [ "$caseI_second" = "Hiddify" ] && [ "$caseI_hid_count" = "1" ]; then
    echo 'fb-caseI-preferred-second-unique:OK'
else
    echo "fb-caseI-preferred-second-unique(2nd='$caseI_second' count=$caseI_hid_count):FAIL"
fi

# (c) Configured UA short-circuits to exactly one line = itself.
caseI_conf="$(build_subscription_user_agent_candidates "MyClient/1.0" "Hiddify")"
caseI_conf_lines="$(printf '%s\n' "$caseI_conf" | grep -c .)"
if [ "$caseI_conf" = "MyClient/1.0" ] && [ "$caseI_conf_lines" = "1" ]; then
    echo 'fb-caseI-configured-only:OK'
else
    echo "fb-caseI-configured-only(got '$caseI_conf' lines=$caseI_conf_lines):FAIL"
fi

# ── CASE J: subscription keyword whitelist/blacklist filter ─────────
# Drive sing_box_cf_prepare_subscription_batch directly with a synthetic
# subscription JSON and assert kept counts/names for include/exclude lists.
# Matching: substring, OR across keywords, ASCII case-insensitive, byte-exact
# for non-folded scripts (emoji/etc). No jq regex (index + inline ucfold only).
caseJ_cfg='{"outbounds":[]}'
caseJ_sub="/tmp/netshift-fb-caseJ-$$.json"
cat > "$caseJ_sub" << 'JSUB'
{
  "outbounds": [
    {"type": "shadowsocks", "tag": "US grpc", "server": "a.example.com", "server_port": 443, "method": "aes-256-gcm", "password": "p"},
    {"type": "shadowsocks", "tag": "US ws", "server": "b.example.com", "server_port": 443, "method": "aes-256-gcm", "password": "p"},
    {"type": "shadowsocks", "tag": "DE grpc", "server": "c.example.com", "server_port": 443, "method": "aes-256-gcm", "password": "p"}
  ]
}
JSUB

# Helper: emit the JSON `count` for given include/exclude arrays.
caseJ_count() {
    sing_box_cf_prepare_subscription_batch "$caseJ_cfg" "$caseJ_sub" "$1" "$2" |
        jq -r '.count // -1'
}
# Helper: emit a comma-joined sorted names list for given include/exclude arrays.
caseJ_names() {
    sing_box_cf_prepare_subscription_batch "$caseJ_cfg" "$caseJ_sub" "$1" "$2" |
        jq -r '(.names // []) | sort | join(",")'
}

# (1) include-only: ["grpc"] keeps exactly the 2 grpc nodes.
caseJ_inc_count="$(caseJ_count '["grpc"]' '[]')"
caseJ_inc_names="$(caseJ_names '["grpc"]' '[]')"
if [ "$caseJ_inc_count" = "2" ] && [ "$caseJ_inc_names" = "DE grpc,US grpc" ]; then
    echo 'fb-caseJ-include-only:OK'
else
    echo "fb-caseJ-include-only(count=$caseJ_inc_count names='$caseJ_inc_names'):FAIL"
fi

# (2) exclude-only: ["ws"] drops the ws node, keeps the other 2.
caseJ_exc_count="$(caseJ_count '[]' '["ws"]')"
caseJ_exc_names="$(caseJ_names '[]' '["ws"]')"
if [ "$caseJ_exc_count" = "2" ] && [ "$caseJ_exc_names" = "DE grpc,US grpc" ]; then
    echo 'fb-caseJ-exclude-only:OK'
else
    echo "fb-caseJ-exclude-only(count=$caseJ_exc_count names='$caseJ_exc_names'):FAIL"
fi

# (3) include + exclude OR: include=["US"], exclude=["ws"] => "US grpc" only.
caseJ_both_count="$(caseJ_count '["US"]' '["ws"]')"
caseJ_both_names="$(caseJ_names '["US"]' '["ws"]')"
if [ "$caseJ_both_count" = "1" ] && [ "$caseJ_both_names" = "US grpc" ]; then
    echo 'fb-caseJ-include-exclude:OK'
else
    echo "fb-caseJ-include-exclude(count=$caseJ_both_count names='$caseJ_both_names'):FAIL"
fi

# (4) case-insensitive ASCII: include=["GRPC"] matches "US grpc"/"DE grpc".
caseJ_ci_count="$(caseJ_count '["GRPC"]' '[]')"
if [ "$caseJ_ci_count" = "2" ]; then
    echo 'fb-caseJ-ascii-ci:OK'
else
    echo "fb-caseJ-ascii-ci(count=$caseJ_ci_count):FAIL"
fi

# (5) emoji/unicode substring: a robot-emoji node kept, a plain node dropped.
caseJ_emoji_sub="/tmp/netshift-fb-caseJ-emoji-$$.json"
cat > "$caseJ_emoji_sub" << 'JEMOJI'
{
  "outbounds": [
    {"type": "shadowsocks", "tag": "🤖 Gemini", "server": "a.example.com", "server_port": 443, "method": "aes-256-gcm", "password": "p"},
    {"type": "shadowsocks", "tag": "Plain Node", "server": "b.example.com", "server_port": 443, "method": "aes-256-gcm", "password": "p"}
  ]
}
JEMOJI
caseJ_emoji_count="$(sing_box_cf_prepare_subscription_batch "$caseJ_cfg" "$caseJ_emoji_sub" '["🤖"]' '[]' | jq -r '.count // -1')"
caseJ_emoji_names="$(sing_box_cf_prepare_subscription_batch "$caseJ_cfg" "$caseJ_emoji_sub" '["🤖"]' '[]' | jq -r '(.names // []) | join(",")')"
if [ "$caseJ_emoji_count" = "1" ] && [ "$caseJ_emoji_names" = "🤖 Gemini" ]; then
    echo 'fb-caseJ-emoji-substring:OK'
else
    echo "fb-caseJ-emoji-substring(count=$caseJ_emoji_count names='$caseJ_emoji_names'):FAIL"
fi
rm -f "$caseJ_emoji_sub"

# (6) empty include keeps all; over-strict filter removes everything (count 0).
caseJ_all_count="$(caseJ_count '[]' '[]')"
if [ "$caseJ_all_count" = "3" ]; then
    echo 'fb-caseJ-empty-include-keeps-all:OK'
else
    echo "fb-caseJ-empty-include-keeps-all(count=$caseJ_all_count):FAIL"
fi
caseJ_none_count="$(caseJ_count '["nomatch-zzz"]' '[]')"
if [ "$caseJ_none_count" = "0" ]; then
    echo 'fb-caseJ-filter-removes-all-zero-kept:OK'
else
    echo "fb-caseJ-filter-removes-all-zero-kept(count=$caseJ_none_count):FAIL"
fi
rm -f "$caseJ_sub"

# ── CASE K: Cyrillic + Ё/ё case-fold (task-010) ─────────────────────
# The keyword filter must fold ASCII AND Cyrillic (inline ucfold), so a
# mixed-case Cyrillic keyword matches a mixed-case Cyrillic server name.
# Emoji keywords still match by exact codepoints; ASCII is unaffected.
caseK_sub="/tmp/netshift-fb-caseK-$$.json"
cat > "$caseK_sub" << 'KSUB'
{
  "outbounds": [
    {"type": "shadowsocks", "tag": "🇩🇪 Германия", "server": "a.example.com", "server_port": 443, "method": "aes-256-gcm", "password": "p"},
    {"type": "shadowsocks", "tag": "🇵🇱 Польша", "server": "b.example.com", "server_port": 443, "method": "aes-256-gcm", "password": "p"},
    {"type": "shadowsocks", "tag": "🇰🇿 Казахстан", "server": "c.example.com", "server_port": 443, "method": "aes-256-gcm", "password": "p"},
    {"type": "shadowsocks", "tag": "Орёл", "server": "d.example.com", "server_port": 443, "method": "aes-256-gcm", "password": "p"},
    {"type": "shadowsocks", "tag": "US grpc", "server": "e.example.com", "server_port": 443, "method": "aes-256-gcm", "password": "p"}
  ]
}
KSUB

caseK_count() {
    sing_box_cf_prepare_subscription_batch "$caseJ_cfg" "$caseK_sub" "$1" "$2" |
        jq -r '.count // -1'
}
caseK_names() {
    sing_box_cf_prepare_subscription_batch "$caseJ_cfg" "$caseK_sub" "$1" "$2" |
        jq -r '(.names // []) | join(",")'
}

# (1) include mixed-case Cyrillic ["ГеРма"] keeps Германия (was 0 before fix).
caseK_mixed_count="$(caseK_count '["ГеРма"]' '[]')"
caseK_mixed_names="$(caseK_names '["ГеРма"]' '[]')"
if [ "$caseK_mixed_count" = "1" ] && [ "$caseK_mixed_names" = "🇩🇪 Германия" ]; then
    echo 'fb-caseK-cyrillic-mixed-include:OK'
else
    echo "fb-caseK-cyrillic-mixed-include(count=$caseK_mixed_count names='$caseK_mixed_names'):FAIL"
fi

# (2) lower ["германия"] and upper ["ГЕРМАНИЯ"] both keep Германия.
caseK_lower_count="$(caseK_count '["германия"]' '[]')"
caseK_upper_count="$(caseK_count '["ГЕРМАНИЯ"]' '[]')"
if [ "$caseK_lower_count" = "1" ] && [ "$caseK_upper_count" = "1" ]; then
    echo 'fb-caseK-cyrillic-lower-upper-include:OK'
else
    echo "fb-caseK-cyrillic-lower-upper-include(lower=$caseK_lower_count upper=$caseK_upper_count):FAIL"
fi

# (3) exclude ["польша"] (lower) drops Польша (upper-P name) regardless of case.
caseK_exc_count="$(caseK_count '[]' '["польша"]')"
caseK_exc_names="$(caseK_names '[]' '["польша"]')"
case "$caseK_exc_names" in
    *Польша*) caseK_exc_has_pl=1 ;;
    *) caseK_exc_has_pl=0 ;;
esac
if [ "$caseK_exc_count" = "4" ] && [ "$caseK_exc_has_pl" = "0" ]; then
    echo 'fb-caseK-cyrillic-exclude:OK'
else
    echo "fb-caseK-cyrillic-exclude(count=$caseK_exc_count names='$caseK_exc_names'):FAIL"
fi

# (4) Ё/ё fold: name "Орёл" matched by lower "орёл" and upper "ОРЁЛ".
caseK_yo_lower="$(caseK_count '["орёл"]' '[]')"
caseK_yo_upper="$(caseK_count '["ОРЁЛ"]' '[]')"
caseK_yo_names="$(caseK_names '["ОРЁЛ"]' '[]')"
if [ "$caseK_yo_lower" = "1" ] && [ "$caseK_yo_upper" = "1" ] && [ "$caseK_yo_names" = "Орёл" ]; then
    echo 'fb-caseK-yo-fold:OK'
else
    echo "fb-caseK-yo-fold(lower=$caseK_yo_lower upper=$caseK_yo_upper names='$caseK_yo_names'):FAIL"
fi

# (5) emoji keyword ["🇰🇿"] keeps Казахстан by exact codepoint match.
caseK_emoji_count="$(caseK_count '["🇰🇿"]' '[]')"
caseK_emoji_names="$(caseK_names '["🇰🇿"]' '[]')"
if [ "$caseK_emoji_count" = "1" ] && [ "$caseK_emoji_names" = "🇰🇿 Казахстан" ]; then
    echo 'fb-caseK-emoji-flag-include:OK'
else
    echo "fb-caseK-emoji-flag-include(count=$caseK_emoji_count names='$caseK_emoji_names'):FAIL"
fi

# (6) ASCII no regression: include ["GRPC"] still keeps the "US grpc" node.
caseK_ascii_count="$(caseK_count '["GRPC"]' '[]')"
caseK_ascii_names="$(caseK_names '["GRPC"]' '[]')"
if [ "$caseK_ascii_count" = "1" ] && [ "$caseK_ascii_names" = "US grpc" ]; then
    echo 'fb-caseK-ascii-no-regression:OK'
else
    echo "fb-caseK-ascii-no-regression(count=$caseK_ascii_count names='$caseK_ascii_names'):FAIL"
fi
rm -f "$caseK_sub"

echo 'DONE'
FBEOF

    sed -i "s|LIB_DIR|$lib|g" "$fb"

    ash "$fb" 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *:OK) pass "$line" ;;
            *:FAIL) fail "$line" ;;
            *:SKIP) skip "$line" ;;
            DONE) ;;
            *) ;;
        esac
    done

    rm -f "$fb"
}

# ─────────────────────────────────────────────────────────────────
# Test: Async component-action job state (updater.sh)
# ─────────────────────────────────────────────────────────────────
# Exercises the jq job-state machinery from updater.sh with a STUBBED worker
# (no network, no real download). A tiny stub CLI sources the real updater.sh,
# provides a trivial `log`, and lets the `component_action` worker be controlled
# by env vars (STUB_JSON / STUB_SLEEP / STUB_RC). component_action_async forks
# `"$0" component_action ...`, so $0 must be the stub CLI itself — hence the
# separate executable. All assertions are jq-validated; tokens are parsed with
# the same name:OK/FAIL convention as test_subscription.
test_jobstate() {
    header "Async Component-Action Job State (updater.sh)"

    if ! command -v jq > /dev/null 2>&1; then
        skip "jq not available"
        return
    fi

    local updater="${NETSHIFT_LIB_DIR}/updater.sh"
    if [ ! -r "$updater" ]; then
        skip "updater.sh not found in ${NETSHIFT_LIB_DIR}"
        return
    fi

    local stub="/tmp/netshift-jobstub-$$"
    cat > "$stub" << 'STUBEOF'
#!/bin/sh
# Minimal stand-in for /usr/bin/netshift that exposes the async job-state API.
log() { :; }
echolog() { :; }
nolog() { :; }
# Isolate state under a per-process tmpfs dir so parallel/old runs never clash.
UPDATES_JOB_DIR="${JOBSTUB_DIR:-/tmp/netshift-jobstub-state}"

. "UPDATER_PATH"

# Re-pin after sourcing (the source sets its own default).
UPDATES_JOB_DIR="${JOBSTUB_DIR:-/tmp/netshift-jobstub-state}"

case "$1" in
component_action)
    # Stubbed worker: emit a (possibly delayed) JSON object then exit STUB_RC.
    [ -n "$STUB_SLEEP" ] && sleep "$STUB_SLEEP"
    if [ -z "$STUB_JSON" ]; then
        STUB_JSON='{"success":true,"version":"1.0.0-extended"}'
    fi
    printf '%s\n' "$STUB_JSON"
    exit "${STUB_RC:-0}"
    ;;
component_action_async)
    component_action_async "$2" "$3"
    ;;
component_action_status)
    component_action_status "$2"
    ;;
esac
STUBEOF
    sed -i "s|UPDATER_PATH|$updater|g" "$stub"
    chmod 0755 "$stub"

    local jdir="/tmp/netshift-jobstate-$$"
    rm -rf "$jdir"

    # ── 1. async returns {success:true, job_id} fast; running state appears ──
    local start_async end_async elapsed async_json job_id
    start_async="$(date +%s)"
    async_json="$(JOBSTUB_DIR="$jdir" STUB_SLEEP=2 STUB_JSON='{"success":true,"version":"1.7.0-extended"}' \
        "$stub" component_action_async sing_box install_extended)"
    end_async="$(date +%s)"
    elapsed=$((end_async - start_async))

    if echo "$async_json" | jq -e '.success == true and (.job_id | length) > 0' > /dev/null 2>&1; then
        pass "async returns success+job_id ($async_json)"
    else
        fail "async did not return success+job_id" "$async_json"
    fi
    if [ "$elapsed" -lt 5 ]; then
        pass "async returned fast (${elapsed}s, well under 30s)"
    else
        fail "async too slow: ${elapsed}s"
    fi

    job_id="$(echo "$async_json" | jq -r '.job_id')"
    if [ -f "$jdir/$job_id.json" ]; then
        pass "running state file created"
    else
        fail "running state file missing: $jdir/$job_id.json"
    fi
    # While the stub sleeps, the state must read running:true / success:true.
    if jq -e '.running == true and .success == true and .exit_code == null' \
            "$jdir/$job_id.json" > /dev/null 2>&1; then
        pass "running state has running:true,success:true,exit_code:null"
    else
        fail "running state shape wrong" "$(cat "$jdir/$job_id.json" 2>/dev/null)"
    fi
    # The recorded pid must be a live integer while running.
    local running_pid
    running_pid="$(jq -r '.pid' "$jdir/$job_id.json" 2>/dev/null)"
    case "$running_pid" in
        '' | *[!0-9]*) fail "running pid not an integer: '$running_pid'" ;;
        *) pass "running pid recorded ($running_pid)" ;;
    esac

    # ── 2. after the worker finishes, status reports the surfaced outcome ────
    # Wait for the background worker (stub sleeps 2s) to complete.
    local waited=0
    while [ "$waited" -lt 15 ]; do
        if jq -e '.running == false' "$jdir/$job_id.json" > /dev/null 2>&1; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    local status_json
    status_json="$(JOBSTUB_DIR="$jdir" "$stub" component_action_status "$job_id")"
    if echo "$status_json" | jq -e '.running == false and .success == true and .exit_code == 0 and .version == "1.7.0-extended"' > /dev/null 2>&1; then
        pass "finished status surfaces success/version/exit_code"
    else
        fail "finished status wrong" "$status_json"
    fi

    # ── 2b. a failing worker is recorded (success:false, non-zero exit) ──────
    local fail_json fail_id fail_status
    fail_json="$(JOBSTUB_DIR="$jdir" STUB_RC=3 STUB_JSON='{"success":false,"message":"boom"}' \
        "$stub" component_action_async sing_box install_extended)"
    fail_id="$(echo "$fail_json" | jq -r '.job_id')"
    waited=0
    while [ "$waited" -lt 15 ]; do
        if jq -e '.running == false' "$jdir/$fail_id.json" > /dev/null 2>&1; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
    fail_status="$(JOBSTUB_DIR="$jdir" "$stub" component_action_status "$fail_id")"
    if echo "$fail_status" | jq -e '.running == false and .success == false and .exit_code == 3 and .message == "boom"' > /dev/null 2>&1; then
        pass "failed worker recorded (success:false, exit_code:3, message surfaced)"
    else
        fail "failed worker status wrong" "$fail_status"
    fi

    # ── 2c. worker stdout polluted with log lines: last JSON object wins ─────
    local noisy_json noisy_id noisy_status
    noisy_json="$(JOBSTUB_DIR="$jdir" \
        STUB_JSON='Updater: some log line
another stray line {not-json}
{"success":true,"version":"9.9.9-extended"}' \
        "$stub" component_action_async sing_box install_extended)"
    noisy_id="$(echo "$noisy_json" | jq -r '.job_id')"
    waited=0
    while [ "$waited" -lt 15 ]; do
        if jq -e '.running == false' "$jdir/$noisy_id.json" > /dev/null 2>&1; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
    noisy_status="$(JOBSTUB_DIR="$jdir" "$stub" component_action_status "$noisy_id")"
    if echo "$noisy_status" | jq -e '.running == false and .success == true and .version == "9.9.9-extended"' > /dev/null 2>&1; then
        pass "finished parser extracts the LAST well-formed JSON object from noisy stdout"
    else
        fail "noisy-stdout parse wrong" "$noisy_status"
    fi

    # ── 3. invalid / traversal job ids are rejected safely ──────────────────
    local bad bad_json bad_rc bad_out="/tmp/netshift-jobstate-bad-$$"
    for bad in "../foo" "../../etc/passwd" "foo/bar" "a b" "" "."; do
        bad_rc=0
        JOBSTUB_DIR="$jdir" "$stub" component_action_status "$bad" > "$bad_out" 2>/dev/null || bad_rc=$?
        bad_json="$(cat "$bad_out" 2>/dev/null)"
        if [ "$bad_rc" -ne 0 ] \
                && echo "$bad_json" | jq -e '.success == false and .running == false' > /dev/null 2>&1; then
            pass "invalid job_id rejected safely: '$bad'"
        else
            fail "invalid job_id NOT rejected: '$bad'" "rc=$bad_rc json=$bad_json"
        fi
    done
    rm -f "$bad_out"
    # The validator must never resolve a traversal id to a path.
    local fb_jobstate="/tmp/netshift-jobstate-validate-$$.sh"
    cat > "$fb_jobstate" << 'VEOF'
log() { :; }
UPDATES_JOB_DIR="VDIR"
. "UPDATER_PATH"
UPDATES_JOB_DIR="VDIR"
if updates_job_state_path "../foo" >/dev/null 2>&1; then
    echo 'jobstate-traversal-rejected:FAIL'
else
    echo 'jobstate-traversal-rejected:OK'
fi
if updates_job_state_path "good-1.2_3" >/dev/null 2>&1; then
    echo 'jobstate-valid-id-accepted:OK'
else
    echo 'jobstate-valid-id-accepted:FAIL'
fi
VEOF
    sed -i "s|UPDATER_PATH|$updater|g;s|VDIR|$jdir|g" "$fb_jobstate"
    ash "$fb_jobstate" 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *:OK) pass "$line" ;;
            *:FAIL) fail "$line" ;;
        esac
    done
    rm -f "$fb_jobstate"

    # ── 4. stale job: running:true with a dead pid past grace → finished ─────
    local stale_dir="$jdir/stale"
    mkdir -p "$stale_dir"
    local stale_state="$stale_dir/staletest.json"
    local stale_sh="/tmp/netshift-jobstate-stale-$$.sh"
    cat > "$stale_sh" << 'SEOF'
log() { :; }
UPDATES_JOB_DIR="SDIR"
. "UPDATER_PATH"
UPDATES_JOB_DIR="SDIR"
state="SSTATE"
# Pick a pid that is certainly dead, and a started_at far in the past so we are
# well beyond the stale grace window.
dead_pid=999999
while kill -0 "$dead_pid" 2>/dev/null; do
    dead_pid=$((dead_pid + 1))
done
old_started=$(( $(date +%s) - 3600 ))
jq -nc --argjson pid "$dead_pid" --argjson started "$old_started" \
    '{success:true,running:true,component:"sing_box",action:"install_extended",
      message:"Component action is running",pid:$pid,started_at:$started,
      updated_at:$started,exit_code:null,version:"",latest_version:""}' > "$state"
updates_refresh_running_job_state "$state"
if jq -e '.running == false and .success == false' "$state" >/dev/null 2>&1; then
    echo 'jobstate-stale-marked-finished:OK'
else
    echo 'jobstate-stale-marked-finished:FAIL'
fi
SEOF
    sed -i "s|UPDATER_PATH|$updater|g;s|SDIR|$stale_dir|g;s|SSTATE|$stale_state|g" "$stale_sh"
    ash "$stale_sh" 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *:OK) pass "$line" ;;
            *:FAIL) fail "$line" ;;
        esac
    done
    rm -f "$stale_sh"

    rm -rf "$jdir" "$stub"
}

# ─────────────────────────────────────────────────────────────────
# Test: Core-switch connectivity self-heal + rollback (updater.sh, task-009)
#
# Fully mocked — no real network, no real package install, no real binary
# touched. A generated driver sources updater.sh, points RESOLV_CONF and the
# tmpfs backup at test files, stubs dig/nslookup/curl/opkg/apk and a fake
# /etc/init.d/netshift via a PATH-prepended bin dir + a writable init stub, and
# drives each scenario via env flags. The driver emits `name:OK`/`name:FAIL`
# tokens which the case parser turns into pass/fail.
# ─────────────────────────────────────────────────────────────────
test_selfheal() {
    header "Core-switch Connectivity Self-Heal + Rollback (updater.sh)"

    if ! command -v jq > /dev/null 2>&1; then
        skip "jq not available"
        return
    fi

    local updater="${NETSHIFT_LIB_DIR}/updater.sh"
    if [ ! -r "$updater" ]; then
        skip "updater.sh not found in ${NETSHIFT_LIB_DIR}"
        return
    fi

    local work="/tmp/netshift-selfheal-$$"
    rm -rf "$work"
    mkdir -p "$work/bin" "$work/init"

    # ── Command stubs (PATH-prepended). Behaviour is driven by env files so the
    # driver can flip them between scenarios without rewriting the stubs. ──────
    #
    # DNS/HTTPS probes: a stub "succeeds" only when its marker file is present.
    cat > "$work/bin/dig" << 'DIGEOF'
#!/bin/sh
# Echo an address (so the resolver-detect grep matches) only if allowed.
[ -f "$SELFHEAL_DNS_OK" ] && { echo "1.2.3.4"; exit 0; }
exit 1
DIGEOF
    cat > "$work/bin/nslookup" << 'NSEOF'
#!/bin/sh
[ -f "$SELFHEAL_DNS_OK" ] && { echo "Address 1.2.3.4"; exit 0; }
exit 1
NSEOF
    cat > "$work/bin/curl" << 'CURLEOF'
#!/bin/sh
# Reachability probe (-I/HEAD). Succeed only when the marker is present.
[ -f "$SELFHEAL_HTTP_OK" ] && exit 0
exit 1
CURLEOF
    # opkg/apk stubs: package "install" succeeds or fails per marker, and on a
    # "successful" stable install they flip the installed core to non-extended.
    cat > "$work/bin/opkg" << 'OPKGEOF'
#!/bin/sh
case "$1" in
update) exit 0 ;;
install)
    if [ -f "$SELFHEAL_PKG_OK" ]; then
        printf 'stable-1.12.0\n' > "$SELFHEAL_CORE_VERSION"
        exit 0
    fi
    # Simulate a package failure that ALSO removed the live binary (the brick
    # scenario): blow away the mock binary so the rollback must restore it.
    rm -f "$SELFHEAL_BIN" 2>/dev/null
    exit 1
    ;;
esac
exit 0
OPKGEOF
    chmod 0755 "$work/bin/dig" "$work/bin/nslookup" "$work/bin/curl" "$work/bin/opkg"

    # Fake /etc/init.d/netshift: records each invocation (stop/start/restart) to
    # a log so the driver can assert teardown/bring-up happened.
    cat > "$work/init/netshift" << 'INITEOF'
#!/bin/sh
printf '%s\n' "$1" >> "$SELFHEAL_INIT_LOG"
exit 0
INITEOF
    chmod 0755 "$work/init/netshift"

    # ── Driver: sources updater, overrides paths/helpers, runs one scenario. ──
    local drv="$work/driver.sh"
    cat > "$drv" << 'DRVEOF'
log() { :; }
echolog() { :; }
nolog() { :; }
updates_log() { :; }
RESOLV_CONF="DRV_RESOLV"
UPDATES_RESOLV_BACKUP="DRV_BACKUP"
UPDATES_FEED_PROBE_HOST="feeds.test"
UPDATES_GITHUB_PROBE_HOST="github.test"
UPDATES_HEAL_RESOLVERS="1.1.1.1 9.9.9.9"
UPDATES_SING_BOX_BIN="$SELFHEAL_BIN"
UPDATES_LIBCRONET_LIB="DRV_CRONET"
. "DRV_UPDATER"
# Re-pin after sourcing (the source sets its own defaults).
RESOLV_CONF="DRV_RESOLV"
UPDATES_RESOLV_BACKUP="DRV_BACKUP"
UPDATES_FEED_PROBE_HOST="feeds.test"
UPDATES_GITHUB_PROBE_HOST="github.test"
UPDATES_HEAL_RESOLVERS="1.1.1.1 9.9.9.9"
UPDATES_SING_BOX_BIN="$SELFHEAL_BIN"
UPDATES_LIBCRONET_LIB="DRV_CRONET"

# Mocked helpers used by the stable core (normally from helpers.sh).
get_sing_box_version() { cat "$SELFHEAL_CORE_VERSION" 2>/dev/null; }
is_sing_box_extended() {
    case "${1:-$(get_sing_box_version)}" in
    *extended*) return 0 ;;
    *) return 1 ;;
    esac
}
# Make the post-install restart a no-op probe (the fake init records it anyway).
updates_restart_netshift() { /etc/init.d/netshift restart >/dev/null 2>&1 || true; }

case "$1" in
run_stable)  updates_install_sing_box_stable ;;
esac
DRVEOF
    sed -i "s|DRV_UPDATER|$updater|g;s|DRV_RESOLV|$work/resolv.conf|g;s|DRV_BACKUP|$work/resolv.bak|g;s|DRV_CRONET|$work/libcronet.so|g" "$drv"

    # Common per-run wiring: PATH-prepended stubs + fake init under /etc/init.d.
    # We back up any real /etc/init.d/netshift and restore it at the end.
    local init_target="/etc/init.d/netshift"
    local init_saved=""
    if [ -e "$init_target" ]; then
        init_saved="$work/netshift.realinit"
        cp -p "$init_target" "$init_saved" 2>/dev/null || init_saved=""
    fi
    mkdir -p /etc/init.d 2>/dev/null || true
    cp -p "$work/init/netshift" "$init_target" 2>/dev/null
    chmod 0755 "$init_target" 2>/dev/null || true

    # Marker/state files shared with the stubs via env.
    export SELFHEAL_DNS_OK="$work/dns_ok"
    export SELFHEAL_HTTP_OK="$work/http_ok"
    export SELFHEAL_PKG_OK="$work/pkg_ok"
    export SELFHEAL_INIT_LOG="$work/init.log"
    export SELFHEAL_CORE_VERSION="$work/core.version"
    export SELFHEAL_BIN="$work/usr-bin-sing-box"

    local out="$work/out.json"

    run_scenario() {
        # The worker returns non-zero on recoverable failures (success:false);
        # under `set -e` that would abort the suite, so swallow the rc here — the
        # assertions read the JSON + file state, not the exit code.
        rm -f "$work/init.log"
        PATH="$work/bin:$PATH" ash "$drv" run_stable > "$out" 2>/dev/null || true
    }

    # ── Scenario 1: pre-flight passes → install proceeds, no teardown ─────────
    : > "$SELFHEAL_DNS_OK"; : > "$SELFHEAL_HTTP_OK"; : > "$SELFHEAL_PKG_OK"
    printf 'extended-1.12.0\n' > "$SELFHEAL_CORE_VERSION"
    printf 'original-resolver\n' > "$work/resolv.conf"
    : > "$work/usr-bin-sing-box"
    run_scenario
    if jq -e '.success == true' "$out" > /dev/null 2>&1; then
        pass "selfheal-preflight-pass-proceeds:OK"
    else
        fail "selfheal-preflight-pass-proceeds:FAIL" "$(cat "$out" 2>/dev/null)"
    fi
    if [ ! -f "$work/init.log" ] || ! grep -q 'stop' "$work/init.log"; then
        pass "selfheal-preflight-pass-no-teardown:OK"
    else
        fail "selfheal-preflight-pass-no-teardown:FAIL" "init.log=$(cat "$work/init.log" 2>/dev/null)"
    fi
    if [ "$(cat "$work/resolv.conf" 2>/dev/null)" = "original-resolver" ]; then
        pass "selfheal-preflight-pass-resolv-untouched:OK"
    else
        fail "selfheal-preflight-pass-resolv-untouched:FAIL" "$(cat "$work/resolv.conf" 2>/dev/null)"
    fi

    # ── Scenario 2: pre-flight fails → DNS heal succeeds → resolv restored ────
    # DNS fails first, but once the temp resolver is written DNS+HTTP pass. We
    # model "temp resolver fixes DNS" by making the DNS probe key off the temp
    # resolver content: the stub succeeds only when the marker exists, and the
    # heal writes the marker via a wrapper. Simpler: DNS off initially, but the
    # heal's resolv write triggers a hook that flips DNS on. We emulate that by
    # having the temp-resolver write observed through resolv.conf content.
    rm -f "$SELFHEAL_DNS_OK"; : > "$SELFHEAL_HTTP_OK"; : > "$SELFHEAL_PKG_OK"
    printf 'extended-1.12.0\n' > "$SELFHEAL_CORE_VERSION"
    printf 'original-resolver\n' > "$work/resolv.conf"
    : > "$work/usr-bin-sing-box"
    # dig stub variant for scenario 2: DNS resolves only once resolv.conf holds
    # the temp resolver (i.e. after the heal wrote it).
    cat > "$work/bin/dig" << 'DIG2EOF'
#!/bin/sh
grep -q '1.1.1.1' "DRV_RESOLV2" 2>/dev/null && { echo "1.2.3.4"; exit 0; }
exit 1
DIG2EOF
    sed -i "s|DRV_RESOLV2|$work/resolv.conf|g" "$work/bin/dig"
    chmod 0755 "$work/bin/dig"
    run_scenario
    if jq -e '.success == true' "$out" > /dev/null 2>&1; then
        pass "selfheal-dns-heal-proceeds:OK"
    else
        fail "selfheal-dns-heal-proceeds:FAIL" "$(cat "$out" 2>/dev/null)"
    fi
    # Epilogue must have restored the ORIGINAL resolv.conf.
    if [ "$(cat "$work/resolv.conf" 2>/dev/null)" = "original-resolver" ]; then
        pass "selfheal-dns-heal-resolv-restored:OK"
    else
        fail "selfheal-dns-heal-resolv-restored:FAIL" "$(cat "$work/resolv.conf" 2>/dev/null)"
    fi
    # DNS heal alone was enough → redirect should NOT have been torn down.
    if [ ! -f "$work/init.log" ] || ! grep -q 'stop' "$work/init.log"; then
        pass "selfheal-dns-heal-no-teardown:OK"
    else
        fail "selfheal-dns-heal-no-teardown:FAIL" "init.log=$(cat "$work/init.log" 2>/dev/null)"
    fi

    # ── Scenario 3: DNS heal insufficient → redirect teardown heals ───────────
    # DNS resolves even with the temp resolver, but HTTP only comes up AFTER the
    # redirect is torn down (the fake init writes a marker on stop that flips
    # HTTP on).
    rm -f "$SELFHEAL_DNS_OK"; rm -f "$SELFHEAL_HTTP_OK"; : > "$SELFHEAL_PKG_OK"
    printf 'extended-1.12.0\n' > "$SELFHEAL_CORE_VERSION"
    printf 'original-resolver\n' > "$work/resolv.conf"
    : > "$work/usr-bin-sing-box"
    # DNS resolves only with temp resolver present (as scenario 2).
    # HTTP succeeds only after init stop has been recorded.
    cat > "$work/bin/curl" << 'CURL3EOF'
#!/bin/sh
grep -q 'stop' "$SELFHEAL_INIT_LOG" 2>/dev/null && exit 0
exit 1
CURL3EOF
    chmod 0755 "$work/bin/curl"
    run_scenario
    if jq -e '.success == true' "$out" > /dev/null 2>&1; then
        pass "selfheal-teardown-heal-proceeds:OK"
    else
        fail "selfheal-teardown-heal-proceeds:FAIL" "$(cat "$out" 2>/dev/null)"
    fi
    if grep -q 'stop' "$work/init.log" 2>/dev/null; then
        pass "selfheal-teardown-taken:OK"
    else
        fail "selfheal-teardown-taken:FAIL" "init.log=$(cat "$work/init.log" 2>/dev/null)"
    fi
    if grep -q 'start' "$work/init.log" 2>/dev/null; then
        pass "selfheal-teardown-bringup-called:OK"
    else
        fail "selfheal-teardown-bringup-called:FAIL" "init.log=$(cat "$work/init.log" 2>/dev/null)"
    fi
    if [ "$(cat "$work/resolv.conf" 2>/dev/null)" = "original-resolver" ]; then
        pass "selfheal-teardown-resolv-restored:OK"
    else
        fail "selfheal-teardown-resolv-restored:FAIL" "$(cat "$work/resolv.conf" 2>/dev/null)"
    fi

    # ── Scenario 4: heal fails entirely → install ABORTED, binary not removed ─
    rm -f "$SELFHEAL_DNS_OK"; rm -f "$SELFHEAL_HTTP_OK"; : > "$SELFHEAL_PKG_OK"
    printf 'extended-1.12.0\n' > "$SELFHEAL_CORE_VERSION"
    printf 'original-resolver\n' > "$work/resolv.conf"
    : > "$work/usr-bin-sing-box"
    # DNS never resolves; HTTP never reachable even after teardown.
    cat > "$work/bin/dig" << 'DIG4EOF'
#!/bin/sh
exit 1
DIG4EOF
    cat > "$work/bin/curl" << 'CURL4EOF'
#!/bin/sh
exit 1
CURL4EOF
    chmod 0755 "$work/bin/dig" "$work/bin/curl"
    run_scenario
    if jq -e '.success == false and (.message | length) > 0' "$out" > /dev/null 2>&1; then
        pass "selfheal-heal-fail-aborts-successfalse:OK"
    else
        fail "selfheal-heal-fail-aborts-successfalse:FAIL" "$(cat "$out" 2>/dev/null)"
    fi
    # The (mock) binary must NOT have been removed (opkg install never ran).
    if [ -e "$work/usr-bin-sing-box" ]; then
        pass "selfheal-heal-fail-binary-intact:OK"
    else
        fail "selfheal-heal-fail-binary-intact:FAIL" "mock binary was removed"
    fi
    # Original resolv.conf restored by the epilogue.
    if [ "$(cat "$work/resolv.conf" 2>/dev/null)" = "original-resolver" ]; then
        pass "selfheal-heal-fail-resolv-restored:OK"
    else
        fail "selfheal-heal-fail-resolv-restored:FAIL" "$(cat "$work/resolv.conf" 2>/dev/null)"
    fi
    # Redirect was torn down during the (failed) heal → epilogue brings it back.
    if grep -q 'start' "$work/init.log" 2>/dev/null; then
        pass "selfheal-heal-fail-bringup-called:OK"
    else
        fail "selfheal-heal-fail-bringup-called:FAIL" "init.log=$(cat "$work/init.log" 2>/dev/null)"
    fi

    # ── Scenario 5: stable install fails after binary removed → backup restored
    : > "$SELFHEAL_DNS_OK"; : > "$SELFHEAL_HTTP_OK"; rm -f "$SELFHEAL_PKG_OK"
    printf 'extended-1.12.0\n' > "$SELFHEAL_CORE_VERSION"
    printf 'original-resolver\n' > "$work/resolv.conf"
    printf 'EXTENDED-CORE-BYTES\n' > "$work/usr-bin-sing-box"
    # Connectivity is fine; dig/curl just check the markers.
    cat > "$work/bin/dig" << 'DIG5EOF'
#!/bin/sh
[ -f "$SELFHEAL_DNS_OK" ] && { echo "1.2.3.4"; exit 0; }
exit 1
DIG5EOF
    cat > "$work/bin/curl" << 'CURL5EOF'
#!/bin/sh
[ -f "$SELFHEAL_HTTP_OK" ] && exit 0
exit 1
CURL5EOF
    chmod 0755 "$work/bin/dig" "$work/bin/curl"
    run_scenario
    if jq -e '.success == false' "$out" > /dev/null 2>&1; then
        pass "selfheal-stable-install-fail-successfalse:OK"
    else
        fail "selfheal-stable-install-fail-successfalse:FAIL" "$(cat "$out" 2>/dev/null)"
    fi
    # The opkg stub removed the live binary; the tmpfs backup must be restored
    # so a working binary remains with the ORIGINAL extended bytes.
    if [ -e "$work/usr-bin-sing-box" ] && \
            [ "$(cat "$work/usr-bin-sing-box" 2>/dev/null)" = "EXTENDED-CORE-BYTES" ]; then
        pass "selfheal-stable-install-fail-backup-restored:OK"
    else
        fail "selfheal-stable-install-fail-backup-restored:FAIL" "$(cat "$work/usr-bin-sing-box" 2>/dev/null)"
    fi

    # ── Restore the real init script (if any) and clean up. ──────────────────
    if [ -n "$init_saved" ] && [ -e "$init_saved" ]; then
        cp -p "$init_saved" "$init_target" 2>/dev/null || true
    else
        rm -f "$init_target" 2>/dev/null || true
    fi
    unset SELFHEAL_DNS_OK SELFHEAL_HTTP_OK SELFHEAL_PKG_OK SELFHEAL_INIT_LOG \
        SELFHEAL_CORE_VERSION SELFHEAL_BIN
    rm -rf "$work"
}

# ─────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────
main() {
    printf "${BOLD}Netshift Evolution — Smoke Test Suite${NC}\n"
    printf "Source: %s\n" "$NETSHIFT_SRC"
    printf "OpenWrt: %s\n" "$(grep OPENWRT_RELEASE /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo 'unknown')"
    printf "Kernel: %s\n" "$(uname -r 2>/dev/null || echo 'unknown')"
    printf "\n"

    local target="${1:-all}"

    case "$target" in
        all)
            test_deps
            test_syntax
            test_config
            test_helpers
            test_jq_helpers
            test_config_manager
            test_sing_box_config
            test_nft
            test_diagnostics
            test_subscription
            test_jobstate
            test_selfheal
            ;;
        deps)        test_deps ;;
        syntax)      test_syntax ;;
        config)      test_config ;;
        helpers)     test_helpers ;;
        nft)         test_nft ;;
        diagnostics) test_diagnostics ;;
        subscription) test_subscription ;;
        jobstate)    test_jobstate ;;
        selfheal)    test_selfheal ;;
        jq)          test_jq_helpers ;;
        cm)          test_config_manager ;;
        sb)          test_sing_box_config ;;
        *)
            echo "Unknown test: $target"
            echo "Available: all deps syntax config helpers jq cm sb nft diagnostics subscription jobstate selfheal"
            exit 1
            ;;
    esac

    summary
}

main "$@"
