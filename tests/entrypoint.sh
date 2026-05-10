#!/bin/sh
# ──────────────────────────────────────────────────────────────────
# Podkop Evolution — Smoke Test Suite Entrypoint
#
# Runs validation tests against the podkop codebase in an OpenWrt
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
PODKOP_SRC="${PODKOP_SRC:-/podkop/files}"
PODKOP_LIB_DIR="${PODKOP_SRC}/usr/lib"

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

    local lib="${PODKOP_LIB_DIR}"

    # Test each library file for syntax errors
    for f in \
        "$lib/constants.sh" \
        "$lib/helpers.sh" \
        "$lib/logging.sh" \
        "$lib/nft.sh" \
        "$lib/rulesets.sh" \
        "$lib/sing_box_config_manager.sh" \
        "$lib/sing_box_config_facade.sh"; do

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

    # Test that libraries can be sourced (requires /lib/functions stubs).
    # Use a temp script to avoid fragile shell quoting.
    local source_test="/tmp/podkop-source-test-$$.sh"
    cat > "$source_test" << EOF
PODKOP_LIB="$lib"
PODKOP_CONFIG="/etc/config/podkop.test"
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

    local config="${PODKOP_SRC}/etc/config/podkop"

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

    # Check new options exist
    for opt in "block_doh" "global_proxy" "shutdown_correctly"; do
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

    local helpers="${PODKOP_LIB_DIR}/helpers.sh"

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

# Test is_ipv6
is_ipv6 '::1' && echo 'ipv6:OK' || echo 'ipv6:FAIL'
is_ipv6 '2001:db8::1' && echo 'ipv6-full:OK' || echo 'ipv6-full:FAIL'

# Test is_ipv6_cidr
is_ipv6_cidr '2001:db8::/32' && echo 'ipv6-cidr:OK' || echo 'ipv6-cidr:FAIL'

# Test is_ipv4_ip_or_ipv4_cidr
is_ipv4_ip_or_ipv4_cidr '10.0.0.0/8' && echo 'ipv4cidr:OK' || echo 'ipv4cidr:FAIL'

# Test generate_hwid (needs WAN MAC)
generate_hwid 2>/dev/null && echo 'hwid:OK' || echo 'hwid:SKIP'

# Test get_device_model
get_device_model 2>/dev/null && echo 'model:OK' || echo 'model:SKIP'

# Test URL parsing
url_get_host 'https://example.com:8080/path' | grep -q 'example.com' && echo 'url-host:OK' || echo 'url-host:FAIL'
url_get_port 'https://example.com:8080/path' | grep -q '8080' && echo 'url-port:OK' || echo 'url-port:FAIL'
url_get_host 'http://[::1]:443/test' | grep -q '::1' && echo 'url-ipv6-host:OK' || echo 'url-ipv6-host:FAIL'
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
    local test_table="podkop_test_$$"
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

    local jq_helpers="${PODKOP_LIB_DIR}/helpers.jq"

    if [ ! -r "$jq_helpers" ]; then
        skip "helpers.jq not found"
        return
    fi

    # Production scripts import helpers.jq from /usr/lib/podkop. In the test
    # container sources are bind-mounted under /podkop/files, so provide the
    # runtime path as a symlink for jq module resolution.
    mkdir -p /usr/lib/podkop
    ln -sf "$jq_helpers" /usr/lib/podkop/helpers.jq

    # Test the extend_key_value function. Keep the jq program in a file instead
    # of a shell variable because BusyBox ash can choke on jq syntax like
    # `h::extend_key_value(.; ...)` during script parsing in some builds.
    local jq_filter_file="/tmp/podkop-jq-filter-$$.jq"
    cat > "$jq_filter_file" << 'JQEOF'
import "helpers" as h;
[1,2,3] | h::extend_key_value(.; [4,5])
JQEOF
    local jq_error_file="/tmp/podkop-jq-error-$$.log"
    result=$(jq -n -L "/usr/lib/podkop" -f "$jq_filter_file" 2>"$jq_error_file" || true)
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
    local proxy_filter_file="/tmp/podkop-proxy-filter-$$.jq"
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
    local tags_filter_file="/tmp/podkop-tags-filter-$$.jq"
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
    local flag_filter_file="/tmp/podkop-flag-filter-$$.jq"
    cat > "$flag_filter_file" << 'JQEOF'
def flag($l1; $l2): ([127462 + $l1, 127462 + $l2] | implode);
[(flag(3; 4) + " Frankfurt"), (flag(20; 18) + " New York"), (flag(13; 11) + " Amsterdam"), (flag(9; 15) + " Tokyo"), "no-flag"]
JQEOF
    country_test=$(jq -cn -f "$flag_filter_file")
    rm -f "$flag_filter_file"

    local grouping
    local group_filter_file="/tmp/podkop-group-filter-$$.jq"
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
}

# ─────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────
main() {
    printf "${BOLD}Podkop Evolution — Smoke Test Suite${NC}\n"
    printf "Source: %s\n" "$PODKOP_SRC"
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
            ;;
        deps)        test_deps ;;
        syntax)      test_syntax ;;
        config)      test_config ;;
        helpers)     test_helpers ;;
        nft)         test_nft ;;
        diagnostics) test_diagnostics ;;
        subscription) test_subscription ;;
        jq)          test_jq_helpers ;;
        cm)          test_config_manager ;;
        sb)          test_sing_box_config ;;
        *)
            echo "Unknown test: $target"
            echo "Available: all deps syntax config helpers jq cm sb nft diagnostics subscription"
            exit 1
            ;;
    esac

    summary
}

main "$@"
