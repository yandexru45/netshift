# Memory — shell-backend-developer

Durable backend (ash + jq) knowledge. Read before implementing; append
findings; keep under ~200 lines.

## Hard constraints (proven)

- **OpenWRT jq has NO Oniguruma** — `test()`, `match()`, `sub()`, `gsub()` and
  any regex are unavailable. The updater (`updater.sh`) documents workarounds.
  Build string logic with `split`/`startswith`/`endswith`/`contains`/`ascii`
  instead.
- **`fatal` is only a log label** — `log "..." "fatal"` does NOT exit. You must
  follow it with `exit 1` yourself. Missing the `exit 1` continues with a
  half-built config.
- **busybox sed lacks `\x` escapes** — use printf-octal workarounds (see
  `helpers.sh` `convert_crlf_to_lf` and BOM stripping). Don't assume GNU sed.
- **Intentional mojibake**: some diagnostic strings (list_update /
  subscription_update / global_check) store emoji/box-drawing as corrupted
  CP1251-ish bytes (e.g. `рџ”„`, `вњ…`, `в”Ѓ`). Preserve the exact existing bytes
  when editing those lines or rendered output changes.

## Conventions (follow exactly)

- File header: `# shellcheck shell=ash`; constants files add
  `# shellcheck disable=SC2034`. Declare every variable `local`.
- Function prefixes: `sing_box_cm_*` = one jq mutation each (dumb primitive);
  `sing_box_cf_*` = facade (parse + several cm_* calls); `url_*` = pure URL
  parsing; `is_*` = predicate returning 0/1; `nft_*` = nft wrapper; `updates_*`
  = updater; `get_*_tag` = deterministic tag builder; `configure_*`/`import_*`/
  `_*_handler` = config_foreach callbacks; leading `_` = private helper.
- Config threading: `$config` is a shell STRING; cm/cf take it as `$1`, echo
  mutated JSON; caller does `config=$(sing_box_cm_... "$config" ...)`.
- jq optional keys: `+ (if $x != "" then {k:$x} else {} end)`. Custom helpers
  in `helpers.jq`, imported `import "helpers" as h {"search":"/usr/lib/netshift"}`.
- Validation is mandatory: write to `*.tmp.$$`, run `sing-box -c <file> check`
  (fatal on fail), `jq -e` for shape, md5sum-compare, then `mv`. Atomic only.
- New constants -> `constants.sh` (grouped Common/nft/sing-box/Lists). Never
  hardcode ports/IPs/marks/paths.
- The service-tag pattern: cm_* functions stamp a transient `__service_tag`
  (`SERVICE_TAG`) on rules; `sing_box_cm_save_config_to_file` strips every
  `__service_tag` via `walk(...)` before writing. Don't leave tags in output.

## Subscription / unavailable-outbound flow (don't leak traffic)

- Many code paths branch on `subscription_outbound_is_unavailable` to emit
  **reject** route rules instead of routes when a subscription is down. Any new
  routing code MUST respect this or it leaks traffic when a sub is unavailable.

## Testing

- Smoke suite is `tests/entrypoint.sh` (run via `smoke-tests` skill). Categories:
  deps syntax config helpers jq cm sb nft diagnostics subscription.
- To add a test: write `test_xyz()` using the `header`/`pass`/`fail`/`skip`
  helpers; add it to `main()`'s `all)` list; add a `case` alias; update the
  usage line and the docker-compose comment. Config-gen and subscription
  parsing changes SHOULD get a smoke test.
- Pre-commit-equivalent: always run the `shellcheck` skill (severity error) on
  touched shell files before handing back.

## Known landmines

- nft proxy chain hardcodes `127.0.0.1:1602` (duplicates the constants).
- VPN `domain_resolver` uses wrong variable `$dns_server`.
- `check_nft` references stale set names (`netshift_domains`) / UCI options that
  don't exist elsewhere — likely copied diagnostic cruft.
