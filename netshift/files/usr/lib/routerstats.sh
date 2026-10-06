# shellcheck shell=ash
#
# The router's own vital signs for the dashboard: how long it has been up, the load,
# the memory, the free space of the flash and /tmp, the temperature. Everything is
# read from /proc, /sys and df: no network, no extra packages.

# Where the numbers come from (the tests point these at a prepared tree).
ROUTER_STATS_PROC="${ROUTER_STATS_PROC:-/proc}"
ROUTER_STATS_SYS="${ROUTER_STATS_SYS:-/sys}"

# The hottest temperature in degrees (integer), or nothing when the board exposes none.
router_temperature() {
    local file value best=""

    for file in "$ROUTER_STATS_SYS"/class/thermal/thermal_zone*/temp "$ROUTER_STATS_SYS"/class/hwmon/hwmon*/temp*_input; do
        [ -r "$file" ] || continue
        value="$(cat "$file" 2> /dev/null)"
        case "$value" in
        '' | *[!0-9-]*) continue ;;
        esac
        # kernels report thousandths of a degree; anything that small is already degrees
        [ "$value" -ge 1000 ] 2> /dev/null && value=$((value / 1000))
        # 0 and absurd values are a sensor that does not work
        [ "$value" -gt 0 ] && [ "$value" -lt 150 ] || continue
        if [ -z "$best" ] || [ "$value" -gt "$best" ]; then
            best="$value"
        fi
    done

    [ -n "$best" ] && echo "$best"
    return 0
}

# Free space in megabytes of a mount point (df -Pk), 0 when unknown.
router_free_mb() {
    local kb

    kb="$(df -Pk "$1" 2> /dev/null | awk 'NR==2 {print $4}')"
    case "$kb" in
    '' | *[!0-9]*) echo 0 ;;
    *) echo $((kb / 1024)) ;;
    esac
}

get_router_stats() {
    local uptime load1 load5 load15 mem_total mem_available temperature cores

    uptime="$(cut -d' ' -f1 "$ROUTER_STATS_PROC"/uptime 2> /dev/null | cut -d. -f1)"
    case "$uptime" in
    '' | *[!0-9]*) uptime=0 ;;
    esac

    set -- $(cat "$ROUTER_STATS_PROC"/loadavg 2> /dev/null)
    load1="${1:-0}"
    load5="${2:-0}"
    load15="${3:-0}"

    mem_total="$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\)[[:space:]]*kB$/\1/p' "$ROUTER_STATS_PROC"/meminfo 2> /dev/null | sed -n '1p')"
    mem_available="$(sed -n 's/^MemAvailable:[[:space:]]*\([0-9]*\)[[:space:]]*kB$/\1/p' "$ROUTER_STATS_PROC"/meminfo 2> /dev/null | sed -n '1p')"
    # an old kernel has no MemAvailable: free + buffers + cache is what it means
    if [ -z "$mem_available" ]; then
        mem_available="$(awk '/^(MemFree|Buffers|Cached):/ {sum += $2} END {print sum + 0}' "$ROUTER_STATS_PROC"/meminfo 2> /dev/null)"
    fi
    case "$mem_total" in
    '' | *[!0-9]*) mem_total=0 ;;
    esac
    case "$mem_available" in
    '' | *[!0-9]*) mem_available=0 ;;
    esac

    cores="$(grep -c '^processor' "$ROUTER_STATS_PROC"/cpuinfo 2> /dev/null)"
    case "$cores" in
    '' | *[!0-9]* | 0) cores=1 ;;
    esac

    temperature="$(router_temperature)"

    jq -n -c \
        --argjson uptime "$uptime" \
        --arg load1 "$load1" --arg load5 "$load5" --arg load15 "$load15" \
        --argjson cores "$cores" \
        --argjson mem_total "$((mem_total / 1024))" --argjson mem_available "$((mem_available / 1024))" \
        --argjson flash_free "$(router_free_mb /)" --argjson tmp_free "$(router_free_mb /tmp)" \
        --arg temperature "$temperature" \
        '{
            uptime_seconds: $uptime,
            load: [($load1 | tonumber? // 0), ($load5 | tonumber? // 0), ($load15 | tonumber? // 0)],
            cpu_cores: $cores,
            ram_total_mb: $mem_total,
            ram_available_mb: $mem_available,
            flash_free_mb: $flash_free,
            tmp_free_mb: $tmp_free,
            temperature_c: (if $temperature == "" then null else ($temperature | tonumber) end)
        }'
}
