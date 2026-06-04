# shellcheck shell=ash
NETSHIFT_LIB="/usr/lib/netshift"
. "$NETSHIFT_LIB/helpers.sh"
. "$NETSHIFT_LIB/sing_box_config_manager.sh"

sing_box_cf_add_dns_server() {
    local config="$1"
    local type="$2"
    local tag="$3"
    local server="$4"
    local domain_resolver="$5"
    local detour="$6"

    local server_address server_port
    server_address=$(url_get_host "$server")
    server_port=$(url_get_port "$server")

    case "$type" in
    udp)
        [ -z "$server_port" ] && server_port=53
        config=$(sing_box_cm_add_udp_dns_server "$config" "$tag" "$server_address" "$server_port" "$domain_resolver" \
            "$detour")
        ;;
    dot)
        [ -z "$server_port" ] && server_port=853
        config=$(sing_box_cm_add_tls_dns_server "$config" "$tag" "$server_address" "$server_port" "$domain_resolver" \
            "$detour")
        ;;
    doh)
        [ -z "$server_port" ] && server_port=443
        local path headers
        path=$(url_get_path "$server")
        headers="" # TODO(ampetelin): implement it if necessary
        config=$(sing_box_cm_add_https_dns_server "$config" "$tag" "$server_address" "$server_port" "$path" "$headers" \
            "$domain_resolver" "$detour")
        ;;
    *)
        log "Unsupported DNS server type: $type. Aborted." "fatal"
        exit 1
        ;;
    esac

    echo "$config"
}

sing_box_cf_add_mixed_inbound_and_route_rule() {
    local config="$1"
    local tag="$2"
    local listen_address="$3"
    local listen_port="$4"
    local outbound="$5"

    config=$(sing_box_cm_add_mixed_inbound "$config" "$tag" "$listen_address" "$listen_port")
    config=$(sing_box_cm_add_route_rule "$config" "" "$tag" "$outbound")

    echo "$config"
}

sing_box_cf_add_proxy_outbound() {
    local config="$1"
    local section="$2"
    local url="$3"
    local udp_over_tcp="$4"

    url=$(url_decode "$url")
    url=$(url_strip_fragment "$url")

    local scheme
    scheme="$(url_get_scheme "$url")"
    case "$scheme" in
    socks4 | socks4a | socks5)
        local tag host port version userinfo username password udp_over_tcp

        tag=$(get_outbound_tag_by_section "$section")
        host=$(url_get_host "$url")
        port=$(url_get_port "$url")
        version="${scheme#socks}"
        if [ "$scheme" = "socks5" ]; then
            userinfo=$(url_get_userinfo "$url")
            if [ -n "$userinfo" ]; then
                username="${userinfo%%:*}"
                password="${userinfo#*:}"
            fi
        fi
        config="$(sing_box_cm_add_socks_outbound \
            "$config" \
            "$tag" \
            "$host" \
            "$port" \
            "$version" \
            "$username" \
            "$password" \
            "" \
            "$([ "$udp_over_tcp" = "1" ] && echo 2)" # if udp_over_tcp is enabled, enable version 2
        )"
        ;;
    vless)
        local tag host port uuid flow packet_encoding
        tag=$(get_outbound_tag_by_section "$section")
        host=$(url_get_host "$url")
        port=$(url_get_port "$url")
        uuid=$(url_get_userinfo "$url")
        flow=$(url_get_query_param "$url" "flow")
        packet_encoding=$(url_get_query_param "$url" "packetEncoding")

        config=$(sing_box_cm_add_vless_outbound "$config" "$tag" "$host" "$port" "$uuid" "$flow" "" "$packet_encoding")
        config=$(_add_outbound_security "$config" "$tag" "$url")
        config=$(_add_outbound_transport "$config" "$tag" "$url")
        ;;
    ss)
        local userinfo tag host port method password udp_over_tcp

        userinfo=$(url_get_userinfo "$url")
        if ! is_shadowsocks_userinfo_format "$userinfo"; then
            userinfo=$(base64_decode "$userinfo")
            if [ $? -ne 0 ]; then
                log "Cannot decode shadowsocks userinfo or it does not match the expected format. Aborted." "fatal"
                exit 1
            fi
        fi

        tag=$(get_outbound_tag_by_section "$section")
        host=$(url_get_host "$url")
        port=$(url_get_port "$url")
        method="${userinfo%%:*}"
        password="${userinfo#*:}"

        config=$(
            sing_box_cm_add_shadowsocks_outbound \
                "$config" \
                "$tag" \
                "$host" \
                "$port" \
                "$method" \
                "$password" \
                "" \
                "$([ "$udp_over_tcp" = "1" ] && echo 2)" # if udp_over_tcp is enabled, enable version 2
        )
        ;;
    trojan)
        local tag host port password
        tag=$(get_outbound_tag_by_section "$section")
        host=$(url_get_host "$url")
        port=$(url_get_port "$url")
        password=$(url_get_userinfo "$url")

        config=$(sing_box_cm_add_trojan_outbound "$config" "$tag" "$host" "$port" "$password")
        config=$(_add_outbound_security "$config" "$tag" "$url")
        config=$(_add_outbound_transport "$config" "$tag" "$url")
        ;;
    hysteria2 | hy2)
        local tag host port password obfuscator_type obfuscator_password upload_mbps download_mbps
        tag=$(get_outbound_tag_by_section "$section")
        host=$(url_get_host "$url")
        port="$(url_get_port "$url")"
        password=$(url_get_userinfo "$url")
        obfuscator_type=$(url_get_query_param "$url" "obfs")
        obfuscator_password=$(url_get_query_param "$url" "obfs-password")
        upload_mbps=$(url_get_query_param "$url" "upmbps")
        download_mbps=$(url_get_query_param "$url" "downmbps")

        config=$(sing_box_cm_add_hysteria2_outbound "$config" "$tag" "$host" "$port" "$password" "$obfuscator_type" \
            "$obfuscator_password" "$upload_mbps" "$download_mbps")
        config=$(_add_outbound_security "$config" "$tag" "$url")
        ;;
    *)
        log "Unsupported proxy $scheme type. Aborted." "fatal"
        exit 1
        ;;
    esac

    echo "$config"
}

_add_outbound_security() {
    local config="$1"
    local outbound_tag="$2"
    local url="$3"

    local security scheme
    security=$(url_get_query_param "$url" "security")
    scheme="$(url_get_scheme "$url")"

    if [ -z "$security" ]; then
        if [ "$scheme" = "hysteria2" ] || [ "$scheme" = "hy2" ]; then
            security="tls"
        fi
    fi

    case "$security" in
    tls | reality)
        local sni insecure alpn fingerprint public_key short_id transport_type
        sni=$(url_get_query_param "$url" "sni")
        insecure=$(_get_insecure_query_param_from_url "$url")
        alpn=$(comma_string_to_json_array "$(url_get_query_param "$url" "alpn")")
        fingerprint=$(url_get_query_param "$url" "fp")
        public_key=$(url_get_query_param "$url" "pbk")
        short_id=$(url_get_query_param "$url" "sid")

        # XHTTP transport defaults its ALPN to h2/http/1.1 when none is provided.
        transport_type=$(url_get_query_param "$url" "type")
        if [ "$transport_type" = "xhttp" ] && [ "$alpn" = "[]" ]; then
            alpn='["h2","http/1.1"]'
        fi

        if [ "$scheme" = "hysteria2" ] || [ "$scheme" = "hy2" ]; then
                fingerprint=""
        fi

        config=$(
            sing_box_cm_set_tls_for_outbound \
                "$config" \
                "$outbound_tag" \
                "$sni" \
                "$([ "$insecure" = "1" ] && echo true)" \
                "$([ "$alpn" = "[]" ] && echo null || echo "$alpn")" \
                "$fingerprint" \
                "$public_key" \
                "$short_id"
        )
        ;;
    none) ;;
    *)
        log "Unknown security '$security' detected." "error"
        ;;
    esac

    echo "$config"
}

_get_insecure_query_param_from_url() {
    local url="$1"

    local insecure
    insecure=$(url_get_query_param "$url" "allowInsecure")
    if [ -z "$insecure" ]; then
        insecure=$(url_get_query_param "$url" "insecure")
    fi

    echo "$insecure"
}

_add_outbound_transport() {
    local config="$1"
    local outbound_tag="$2"
    local url="$3"

    local transport
    transport=$(url_get_query_param "$url" "type")
    case "$transport" in
    tcp | raw) ;;
    ws)
        local ws_path ws_host ws_early_data
        ws_path=$(url_get_query_param "$url" "path")
        ws_host=$(url_get_query_param "$url" "host")
        ws_early_data=$(url_get_query_param "$url" "ed")

        config=$(
            sing_box_cm_set_ws_transport_for_outbound "$config" "$outbound_tag" "$ws_path" "$ws_host" "$ws_early_data"
        )
        ;;
    grpc)
        # TODO(ampetelin): Add handling of optional gRPC parameters; example links are needed.
        local grpc_service_name
        grpc_service_name=$(url_get_query_param "$url" "serviceName")

        config=$(
            sing_box_cm_set_grpc_transport_for_outbound "$config" "$outbound_tag" "$grpc_service_name"
        )
        ;;
    xhttp)
        if ! is_sing_box_extended; then
            log "XHTTP transport requires sing-box-extended. Install sing-box-extended and retry." "error"
            echo "$config"
            return 0
        fi
        local xhttp_path xhttp_host xhttp_sni xhttp_mode
        xhttp_path=$(url_get_query_param "$url" "path")
        xhttp_host=$(url_get_query_param "$url" "host")
        xhttp_sni=$(url_get_query_param "$url" "sni")
        [ -n "$xhttp_host" ] || xhttp_host="$xhttp_sni"
        xhttp_mode=$(url_get_query_param "$url" "mode")
        config=$(sing_box_cm_set_xhttp_transport_for_outbound "$config" "$outbound_tag" "$xhttp_path" "$xhttp_host" "$xhttp_mode")
        ;;
    *)
        log "Unknown transport '$transport' detected." "error"
        ;;
    esac

    echo "$config"
}

sing_box_cf_add_json_outbound() {
    local config="$1"
    local section="$2"
    local json_outbound="$3"

    local tag
    tag=$(get_outbound_tag_by_section "$section")

    config=$(sing_box_cm_add_raw_outbound "$config" "$tag" "$json_outbound")

    echo "$config"
}

sing_box_cf_add_interface_outbound() {
    local config="$1"
    local section="$2"
    local interface_name="$3"

    local tag
    tag=$(get_outbound_tag_by_section "$section")

    config=$(sing_box_cm_add_interface_outbound "$config" "$tag" "$interface_name")

    echo "$config"
}

sing_box_cf_proxy_domain() {
    local config="$1"
    local inbound="$2"
    local domain="$3"
    local outbound="$4"

    tag="$(gen_id)"
    config=$(sing_box_cm_add_route_rule "$config" "$tag" "$inbound" "$outbound")
    config=$(sing_box_cm_patch_route_rule "$config" "$tag" "domain" "$domain")

    echo "$config"
}

sing_box_cf_override_domain_port() {
    local config="$1"
    local domain="$2"
    local port="$3"

    tag="$(gen_id)"
    config=$(sing_box_cm_add_options_route_rule "$config" "$tag")
    config=$(sing_box_cm_patch_route_rule "$config" "$tag" "domain" "$domain")
    config=$(sing_box_cm_patch_route_rule "$config" "$tag" "override_port" "$port")

    echo "$config"
}

sing_box_cf_add_single_key_reject_rule() {
    local config="$1"
    local inbound="$2"
    local key="$3"
    local value="$4"

    tag="$(gen_id)"
    config=$(sing_box_cm_add_reject_route_rule "$config" "$tag" "$inbound")
    config=$(sing_box_cm_patch_route_rule "$config" "$tag" "$key" "$value")

    echo "$config"
}

#######################################
# Build a prepared subscription batch in a SINGLE jq pass.
# Filters out non-proxy types (selector, urltest, direct, dns, block), statically
# drops outbounds unsupported by the current sing-box build (shadowsocks+tls and,
# unless running sing-box-extended, xhttp transport), assigns a unique tag to each
# outbound (deduplicating against tags already present in $config and against tags
# chosen earlier in the same batch) and records a human-readable display name.
# Arguments:
#   config: string (JSON), sing-box configuration the batch will be merged into
#   subscription_json_path: string, path to the downloaded subscription JSON file
#   include_keywords_json: string (JSON array), keep only nodes whose display name
#       contains at least one of these (OR). Empty array ([]) = keep all.
#   exclude_keywords_json: string (JSON array), drop any node whose display name
#       contains at least one of these (OR). Empty array ([]) = no exclusion.
# Outputs:
#   Writes a JSON object to stdout:
#     { outbounds: [ {type,...,tag} ... ], tags: [..], names: [..],
#       count: <kept>, skipped: <statically dropped> }
#######################################
sing_box_cf_prepare_subscription_batch() {
    local config="$1"
    local subscription_json_path="$2"
    local include_keywords_json="${3:-[]}"
    local exclude_keywords_json="${4:-[]}"
    local sing_box_extended="false"

    [ -n "$include_keywords_json" ] || include_keywords_json="[]"
    [ -n "$exclude_keywords_json" ] || exclude_keywords_json="[]"

    if is_sing_box_extended; then
        sing_box_extended="true"
    fi

    # The working config is fed on stdin (POSIX-safe, no process substitution);
    # the subscription JSON is slurped from its file path.
    printf '%s' "$config" | jq -c \
        --slurpfile sub "$subscription_json_path" \
        --argjson extended "$sing_box_extended" \
        --argjson include_keywords "$include_keywords_json" \
        --argjson exclude_keywords "$exclude_keywords_json" '
        # Normalise the keyword lists: drop empty items and precompute the
        # ASCII-lowercased form once. ascii_downcase only touches ASCII, so
        # emoji/Cyrillic keywords are matched as exact byte-substrings.
        # NB: "include"/"exclude" are reserved jq keywords, hence $inc/$exc.
        ([$include_keywords[]? | tostring | select(length > 0) | ascii_downcase]) as $inc
        | ([$exclude_keywords[]? | tostring | select(length > 0) | ascii_downcase]) as $exc
        # A node "matches" a normalised keyword list when its lowercased name
        # contains any of the keywords (substring via index, NO regex/Oniguruma).
        # Bind each keyword to $kw so index() receives the keyword, not the name.
        | def name_passes_keywords($lc):
            (($inc | length) == 0 or any($inc[]; . as $kw | ($lc | index($kw)) != null))
            and (($exc | length) == 0 or all($exc[]; . as $kw | ($lc | index($kw)) == null));
        # Reserved tags already used by the working config (stdin is the config).
        ([.outbounds[]?.tag // empty]) as $existing
        # Candidate proxy outbounds from the subscription (preserve order).
        | [$sub[0].outbounds[]? | select(
            .type != "selector" and
            .type != "urltest" and
            .type != "direct" and
            .type != "dns" and
            .type != "block"
          )] as $all_candidates
        # Keyword whitelist/blacklist filter on the display name. Runs BEFORE the
        # static-unsupported filter and tag dedup, so dropped nodes never get
        # tags and never reach sing-box check. Covers native + fallback-parsed
        # subscriptions (both consume this batch).
        | [$all_candidates[]
            | . as $ob
            | (($ob.remark // $ob.tag // "") | tostring) as $name
            | select(name_passes_keywords($name | ascii_downcase))
          ] as $candidates
        | ($candidates | length) as $total
        # Statically reject outbounds the current sing-box build cannot load.
        | [ $candidates[]
            | . as $ob
            | (($ob.remark // $ob.tag // "") | tostring) as $name
            | if ($ob.type == "shadowsocks" and ($ob.tls.enabled == true)) then
                empty
              elif (($ob.transport.type // "") == "xhttp" and ($extended | not)) then
                empty
              else
                {ob: $ob, name: $name}
              end
          ] as $kept
        # Assign unique tags using a deterministic dedup pass. $state.used is a
        # set (object) of tags already taken, seeded with the existing config tags.
        | reduce range(0; ($kept | length)) as $i (
            {used: ($existing | map({(.): true}) | add // {}), out: []};
            . as $state
            | $kept[$i] as $entry
            | ($entry.ob) as $ob
            | (($ob.tag // $ob.remark // "") | tostring) as $raw
            | (if ($raw | length) > 0 then $raw else ("server-" + (($i + 1) | tostring)) end) as $base
            # Pick $base if free, else the first $base-N (N>=1) that is not taken.
            | (
                if ($state.used[$base] | not) then $base
                else
                    (label $found
                        | (range(1; 1000001)
                            | ($base + "-" + (. | tostring)) as $cand
                            | if ($state.used[$cand] | not) then $cand, break $found else empty end))
                end
              ) as $tag
            | .used[$tag] = true
            | .out += [{
                tag: $tag,
                name: (if ($entry.name | length) > 0 then $entry.name else $tag end),
                outbound: ($ob | del(.tag) | del(.remark) | . + {tag: $tag})
              }]
          ) as $resolved
        | {
            outbounds: [$resolved.out[].outbound],
            tags: [$resolved.out[].tag],
            names: [$resolved.out[].name],
            count: ($resolved.out | length),
            skipped: ($total - ($resolved.out | length))
          }
    ' 2>/dev/null
}

#######################################
# Try to append a slice of prepared outbounds to the config and validate it once
# with a single `sing-box check`. On success the validated config (including the
# appended outbounds) is exposed via SING_BOX_CF_TRY_CONFIG.
# Arguments:
#   config: string (JSON), base configuration to append to
#   outbounds_json: string (JSON array), outbound objects to append (already tagged)
# Returns:
#   0 on success (SING_BOX_CF_TRY_CONFIG set), non-zero on validation failure
#######################################
sing_box_cf_try_subscription_batch() {
    local config="$1"
    local outbounds_json="$2"
    local updated_config validation_tmp

    SING_BOX_CF_TRY_CONFIG=""

    updated_config=$(printf '%s' "$config" | jq -c --argjson new "$outbounds_json" '.outbounds += $new' 2>/dev/null)
    if [ -z "$updated_config" ]; then
        return 1
    fi

    validation_tmp="$(mktemp)" || return 1
    sing_box_cm_save_config_to_file "$updated_config" "$validation_tmp"
    if ! sing-box -c "$validation_tmp" check > /dev/null 2>&1; then
        rm -f "$validation_tmp"
        return 1
    fi
    rm -f "$validation_tmp"

    SING_BOX_CF_TRY_CONFIG="$updated_config"
    return 0
}

#######################################
# Recursively validate a range of prepared outbounds, isolating and skipping the
# ones the current sing-box build rejects. Mirrors podkop-plus' bisection design:
# a clean range costs a single `sing-box check`; only ranges containing a bad
# outbound are split further (groups <= 8 are probed one-by-one).
# Reads/updates the SING_BOX_CF_BATCH_* globals set up by the caller.
# Arguments:
#   start: integer, first index (0-based) into SING_BOX_CF_BATCH_OUTBOUNDS
#   count: integer, number of outbounds in the range
#######################################
sing_box_cf_apply_subscription_range() {
    local start="$1"
    local count="$2"
    local slice display_name half rest index

    [ "$count" -gt 0 ] || return 0

    slice=$(printf '%s' "$SING_BOX_CF_BATCH_OUTBOUNDS" |
        jq -c --argjson start "$start" --argjson count "$count" '.[$start:($start + $count)]' 2>/dev/null)
    if [ -z "$slice" ] || [ "$slice" = "[]" ]; then
        SING_BOX_CF_BATCH_SKIPPED=$((SING_BOX_CF_BATCH_SKIPPED + count))
        return 0
    fi

    if sing_box_cf_try_subscription_batch "$SING_BOX_CF_BATCH_CONFIG" "$slice"; then
        SING_BOX_CF_BATCH_CONFIG="$SING_BOX_CF_TRY_CONFIG"
        SING_BOX_CF_BATCH_KEPT=$((SING_BOX_CF_BATCH_KEPT + count))
        SING_BOX_CF_BATCH_KEPT_RANGES="$SING_BOX_CF_BATCH_KEPT_RANGES $start:$count"
        return 0
    fi

    if [ "$count" -eq 1 ]; then
        display_name=$(printf '%s' "$SING_BOX_CF_BATCH_NAMES" |
            jq -r --argjson start "$start" '.[$start] // "unknown"' 2>/dev/null)
        [ -n "$display_name" ] || display_name="unknown"
        log "Skip unsupported outbound for current sing-box: '$display_name'" "warn"
        SING_BOX_CF_BATCH_SKIPPED=$((SING_BOX_CF_BATCH_SKIPPED + 1))
        return 0
    fi

    if [ "$count" -le 8 ]; then
        index=0
        while [ "$index" -lt "$count" ]; do
            sing_box_cf_apply_subscription_range $((start + index)) 1
            index=$((index + 1))
        done
        return 0
    fi

    half=$((count / 2))
    [ "$half" -gt 0 ] || half=1
    rest=$((count - half))
    sing_box_cf_apply_subscription_range "$start" "$half"
    sing_box_cf_apply_subscription_range $((start + half)) "$rest"
}

#######################################
# Parse a sing-box subscription JSON and add all proxy outbounds to the configuration.
# Filters out non-proxy types (selector, urltest, direct, dns, block).
# Uses 'tag' field (or 'remark' if present) as display name for each outbound.
#
# Validation strategy: build every outbound in a single jq pass, then validate the
# whole batch with one `sing-box check`. If that passes (the common case) the run
# costs O(1) sing-box invocations instead of O(n). If it fails, recursively bisect
# the batch to isolate and skip only the outbounds the current sing-box build
# cannot load, preserving the previous "skip unsupported outbound" behaviour. A
# final full-config validation still happens later in sing_box_save_config().
# Arguments:
#   config: string (JSON), sing-box configuration to modify
#   section: string, the UCI section name
#   subscription_json_path: string, path to the downloaded subscription JSON file
#   include_keywords_json: string (JSON array, optional), keyword whitelist (OR);
#       empty/[] keeps all nodes. Forwarded to the prepare batch.
#   exclude_keywords_json: string (JSON array, optional), keyword blacklist (OR);
#       empty/[] excludes nothing. Forwarded to the prepare batch.
# Outputs:
#   Writes updated JSON configuration to stdout
#   Sets global variable SUBSCRIPTION_OUTBOUND_TAGS (comma-separated list of tags)
#   Sets global variable SUBSCRIPTION_OUTBOUND_TAGS_JSON (JSON array of tags, ASCII-escaped)
#   Sets global variable SUBSCRIPTION_OUTBOUND_NAMES (newline-separated list of display names)
#######################################
sing_box_cf_add_subscription_outbounds() {
    local config="$1"
    local section="$2"
    local subscription_json_path="$3"
    local include_keywords_json="${4:-[]}"
    local exclude_keywords_json="${5:-[]}"

    [ -n "$include_keywords_json" ] || include_keywords_json="[]"
    [ -n "$exclude_keywords_json" ] || exclude_keywords_json="[]"

    SUBSCRIPTION_OUTBOUND_TAGS=""
    SUBSCRIPTION_OUTBOUND_TAGS_JSON="[]"
    SUBSCRIPTION_OUTBOUND_NAMES=""
    SING_BOX_CF_LAST_CONFIG="$config"

    if [ ! -f "$subscription_json_path" ]; then
        log "Subscription JSON file not found: $subscription_json_path" "error"
        echo "$config"
        return 1
    fi

    # Whether keyword filtering is active (for distinct empty-result logging).
    local keyword_filter_active=0
    if [ "$include_keywords_json" != "[]" ] || [ "$exclude_keywords_json" != "[]" ]; then
        keyword_filter_active=1
    fi

    # Build the entire batch (keyword filter + static filter + dedup tags) in one
    # jq pass.
    local prepared
    prepared=$(sing_box_cf_prepare_subscription_batch "$config" "$subscription_json_path" \
        "$include_keywords_json" "$exclude_keywords_json")
    if [ -z "$prepared" ]; then
        log "Failed to parse subscription outbounds JSON" "error"
        echo "$config"
        return 1
    fi

    local candidate_total kept_count statically_skipped
    candidate_total=$(printf '%s' "$prepared" | jq -r '(.count // 0) + (.skipped // 0)' 2>/dev/null)
    kept_count=$(printf '%s' "$prepared" | jq -r '.count // 0' 2>/dev/null)
    statically_skipped=$(printf '%s' "$prepared" | jq -r '.skipped // 0' 2>/dev/null)

    if [ "$keyword_filter_active" -eq 1 ]; then
        # candidate_total here is the post-keyword-filter candidate count; report
        # kept vs. filtered_out so an over-strict filter is diagnosable.
        local raw_candidate_total filtered_out
        raw_candidate_total=$(printf '%s' "$config" | jq -c \
            --slurpfile sub "$subscription_json_path" \
            '[$sub[0].outbounds[]? | select(.type != "selector" and .type != "urltest" and .type != "direct" and .type != "dns" and .type != "block")] | length' 2>/dev/null)
        [ -n "$raw_candidate_total" ] || raw_candidate_total=0
        filtered_out=$((raw_candidate_total - candidate_total))
        [ "$filtered_out" -ge 0 ] || filtered_out=0
        log "Subscription keyword filter for section '$section': kept=$candidate_total, filtered_out=$filtered_out" "info"
    fi

    if [ -z "$candidate_total" ] || [ "$candidate_total" -eq 0 ]; then
        if [ "$keyword_filter_active" -eq 1 ]; then
            log "Subscription keyword filter for section '$section' removed all nodes; using a temporary blocked outbound" "warn"
        fi
        log "No proxy outbounds found in subscription JSON" "error"
        echo "$config"
        return 1
    fi

    log "Found $candidate_total proxy outbounds in subscription" "info"

    if [ "${statically_skipped:-0}" -gt 0 ]; then
        log "Skip $statically_skipped subscription outbound(s) unsupported by current sing-box build" "warn"
    fi

    if [ -z "$kept_count" ] || [ "$kept_count" -eq 0 ]; then
        log "No supported proxy outbounds remained in subscription JSON" "error"
        echo "$config"
        return 1
    fi

    # Set up shared state for the (possibly recursive) batch validation.
    SING_BOX_CF_BATCH_CONFIG="$config"
    SING_BOX_CF_BATCH_OUTBOUNDS=$(printf '%s' "$prepared" | jq -c '.outbounds' 2>/dev/null)
    SING_BOX_CF_BATCH_NAMES=$(printf '%s' "$prepared" | jq -c '.names' 2>/dev/null)
    SING_BOX_CF_BATCH_KEPT=0
    SING_BOX_CF_BATCH_SKIPPED=0
    SING_BOX_CF_BATCH_KEPT_RANGES=""

    sing_box_cf_apply_subscription_range 0 "$kept_count"

    if [ "$SING_BOX_CF_BATCH_KEPT" -eq 0 ]; then
        log "No valid subscription outbounds remained after validation for section '$section'" "error"
        echo "$config"
        return 1
    fi

    config="$SING_BOX_CF_BATCH_CONFIG"

    if [ "$SING_BOX_CF_BATCH_SKIPPED" -gt 0 ]; then
        log "Skipped $SING_BOX_CF_BATCH_SKIPPED unsupported subscription outbound(s) during validation" "warn"
    fi

    # Derive the public tag/name globals from the outbounds that were actually
    # added (the ranges accepted during bisection), preserving original order.
    local kept_ranges_json
    kept_ranges_json=$(
        printf '%s' "$SING_BOX_CF_BATCH_KEPT_RANGES" |
            tr ' ' '\n' |
            jq -R 'select(length > 0) | split(":") | {start: (.[0] | tonumber), count: (.[1] | tonumber)}' |
            jq -sc '.'
    )
    [ -n "$kept_ranges_json" ] || kept_ranges_json="[]"

    SUBSCRIPTION_OUTBOUND_TAGS_JSON=$(
        printf '%s' "$prepared" | jq -c --argjson ranges "$kept_ranges_json" \
            '[.tags as $t | $ranges[] | range(.start; .start + .count) | $t[.]]' 2>/dev/null
    )
    [ -n "$SUBSCRIPTION_OUTBOUND_TAGS_JSON" ] || SUBSCRIPTION_OUTBOUND_TAGS_JSON="[]"

    SUBSCRIPTION_OUTBOUND_TAGS=$(
        printf '%s' "$SUBSCRIPTION_OUTBOUND_TAGS_JSON" | jq -r 'join(",")' 2>/dev/null
    )

    SUBSCRIPTION_OUTBOUND_NAMES=$(
        printf '%s' "$prepared" | jq -r --argjson ranges "$kept_ranges_json" \
            '[.names as $n | $ranges[] | range(.start; .start + .count) | $n[.]] | join("\n")' 2>/dev/null
    )

    log "Added $SING_BOX_CF_BATCH_KEPT subscription outbounds for section '$section'" "info"
    SING_BOX_CF_LAST_CONFIG="$config"

    echo "$config"
}
