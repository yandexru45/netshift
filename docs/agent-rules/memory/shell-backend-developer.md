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
- **Diagnostic strings are UTF-8, NOT mojibake** (corrected by task-004). The
  emoji/box-drawing in `usr/bin/netshift` (`global_check`, `list_update`,
  `subscription_update`, `check_nft`: `📡 🛠️ ✅ ❌ ⚠️ ➡️ 🧱 🥸 📄 ━`) are valid
  UTF-8 and must STAY valid UTF-8. They were once double-encoded (UTF-8 read as
  CP1251, re-saved as UTF-8 → printed `рџ…`/`в”…`/`вЂ…`). Never open/save that file
  in a non-UTF-8 editor or pass it through CP1251 — it re-corrupts. The earlier
  "preserve the corrupted bytes" note here was the WRONG guidance that protected
  the bug.

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

## jq gotchas (proven by task-002)

- **`include` / `exclude` are RESERVED jq keywords** — you cannot name a jq
  variable `$include` (jq tries to parse the `include` directive). Use `$inc`/
  `$exc` etc. for keyword-filter lists.
- **`any(gen; cond)` / `all(gen; cond)` binding trap**: inside the condition,
  `.` is the generator element ONLY at the top of `cond`. If you write
  `($name | index(.))` the `.` becomes `$name` (the pipe rebinds `.`), so the
  match silently always succeeds. Bind first: `any($kw[]; . as $k | ($name |
  index($k)) != null)`.
- Subscription keyword filter lives in `sing_box_cf_prepare_subscription_batch`
  (facade), runs BEFORE static-unsupported filter + tag dedup, threaded from the
  `subscription)` branch via two UCI **list** options
  `subscription_filter_include_keywords` / `subscription_filter_exclude_keywords`
  (the cross-layer contract names for task-003 — do NOT rename). Keywords are
  opaque user text: collect with a `config_list_foreach` handler that jq
  `--arg`-appends each item into a JSON array (commas/emoji survive; never use
  `comma_string_to_json_array` for them). Empty result reuses the existing
  `mark_subscription_outbound_unavailable` fail-safe (no `exit 1`).

## Known landmines

- nft proxy chain hardcodes `127.0.0.1:1602` (duplicates the constants).
- VPN `domain_resolver` uses wrong variable `$dns_server`.
- `check_nft` references stale set names (`netshift_domains`) / UCI options that
  don't exist elsewhere — likely copied diagnostic cruft.

## task-004: double-encode repair recipe (reusable)

- To reverse a UTF-8→CP1251 double-encode losslessly: `text =
  bytes.decode("utf-8"); fixed = text.encode("cp1251").decode("utf-8")` then
  write `fixed.encode("utf-8")`. ASCII bytes pass through; verify 0
  cp1251-unmappable chars and that ASCII-stripped lines are byte-identical
  before/after (proves no code moved). Result was exactly 114 lines, all
  non-ASCII-only. LF/no-BOM preserved.
- On Windows here, `python3.exe` is the MS Store stub — use `python` (Python
  3.11 at `...\Programs\Python\Python311`). Don't `print()` emoji to the
  PowerShell console (cp1251 codepage mangles it / raises); write results to a
  UTF-8 file and read it back.
## task-005 review-001: vmess base64 + url_decode landmine (proven)

- `sing_box_cf_add_proxy_outbound` runs `url=$(url_decode "$url")` BEFORE the
  scheme `case`, and `url_decode` does `s/+/ /g`. Any scheme that base64-decodes
  the WHOLE payload (vmess `vmess://base64(JSON)`; future tuic/etc.) MUST decode
  from the RAW link, not the url_decode'd one — standard base64's alphabet
  includes `+`, so `+`→space corrupts ~1-in-64 real keys. Fix pattern: capture
  `local raw_url="$3"` at the top (before url_decode) and pass `$raw_url` to the
  whole-payload decoder. Other scheme cases keep using the url_decode'd `$url`.
- **busybox `tr` does NOT support POSIX char classes** — `tr -d '[:space:]'`
  deletes the LITERAL chars `[ : s p a c e ]` (silently corrupts base64!). Use
  explicit bytes: `tr -d ' \011\012\015'` (space/tab/LF/CR octal). Verified
  in-container: input `aZ:[]cept123` → `Zt123` with `[:space:]`. This was a real
  regression I introduced and caught via the `sb` smoke run.
- base64 padding normalization for unpadded links: right-pad payload length to a
  multiple of 4 with `=` using `pad=$(( ${#p} % 4 ))` then a `while` append loop.
  POSIX-safe, busybox-safe.
- To craft a base64 body that DELIBERATELY contains `+`: a `ps`/label value of
  `node>>` (bytes 0x3E 0x3E) forces a 6-bit group = 62 → `+`. Realistic ASCII
  host/word values rarely hit it; `>>` is reliable.
- Probing helpers in-container without fighting PowerShell quoting: write a tiny
  `.sh` into `netshift/files/usr/lib/` (it's bind-mounted into the smoke
  container at `/netshift/files`), run via
  `docker compose ... run --rm --entrypoint sh netshift-test /netshift/files/usr/lib/_tmp.sh`,
  then delete it. Inline `-c "..."` one-liners get mangled by PowerShell.

- `test_syntax` in `tests/entrypoint.sh` now also `ash -n`'s `usr/bin/netshift`
  and asserts no residual `рџ`/`в”`/`вЂ` markers (built via `printf` octal, since
  busybox grep lacks `\x`). Guards against re-introducing the mojibake.

## task-007: async component-action job state (rpcd 30s wall fix)

- Root cause of "core switch fails": the UI called `component_action sing_box
  install_extended` SYNCHRONOUSLY via rpcd `fs.exec`; rpcd has `-t 30` and kills
  the worker mid-extract (after `tar -O > /usr/bin/sing-box`, before
  `chmod 0755`). The JS-side `timeout: 600000` does NOT help (server-side limit).
  Fix = fork the worker detached; return a job_id in <<30s; poll status.
- Job-state machinery lives in `updater.sh` (jq, no ucode — podkop-plus uses
  `json_utils_ucode` which we don't have). State dir `/var/run/netshift/
  component-actions` (tmpfs). Constants: `UPDATES_JOB_DIR`,
  `UPDATES_JOB_FINISHED_TTL_MINUTES=60`, `UPDATES_JOB_ORPHAN_OUTPUT_TTL_MINUTES=60`,
  `UPDATES_JOB_STALE_GRACE_SECONDS=15`.
- **State object contract (STABLE — frontend task-008 depends on these field
  names):** `{ success, running, component, action, message, pid, started_at,
  updated_at, exit_code, version, latest_version }`. running:
  `running:true,success:true,exit_code:null`. finished: `running:false`,
  success/version/message parsed from the worker stdout JSON, exit_code from `$?`.
- HUP-proof fork: `( trap '' HUP; "$0" component_action "$c" "$a" >"$out" 2>&1;
  updates_write_finished_job_state ... "$?" "$out" ) >/dev/null 2>&1 &`; record
  `$!` into the running state via `updates_update_running_job_pid`. `trap '' HUP`
  is what survives the rpcd session close. The async wrapper NEVER `exit 1`s on a
  worker failure — the failure is recorded in the finished state.
- finished-state stdout parser (`updates_extract_worker_json`): `updates_log`/
  `echolog` can pollute the worker's stdout, so: (1) if the WHOLE file is valid
  JSON (`jq -e .`) use it; else (2) `sed -n 's/^[^{]*\({.*\)$/\1/p' | tail -n 1`
  then `jq -e` validate. sed is busybox-safe; NO Oniguruma. success derives from
  `$w.success // ($exit_code == 0)`; version from `$w.version // $w.current_version`.
- Path-traversal guard: `updates_job_state_path` rejects ids matching
  `*[!A-Za-z0-9._-]*` or empty/`.`/`..` → return 1. The id comes straight from
  the (ACL-gated) UI, so this is the security boundary. `component_action_status`
  returns a safe self-contained `{success:false,running:false,...}` (via
  `updates_job_status_response`, non-zero rc) for invalid id / missing file.
- Stale detection (`updates_refresh_running_job_state`): running:true but pid not
  `kill -0` alive AND past `started_at + STALE_GRACE` → rewrite as finished/stale
  (`success:false`). Prevents the UI polling a crashed worker forever.
- Idempotent install (Req 4): at the START of `updates_install_sing_box_extended`,
  if `/usr/bin/sing-box` exists but is not `-x` OR fails a `version` probe, `rm`
  it up front (don't back up a broken partial artifact). `chmod 0755` stays
  IMMEDIATELY after stream-extract and BEFORE validation — keep that order.
- **`set -e` + command substitution landmine (smoke harness):** under `set -e`,
  `x="$(cmd-that-returns-nonzero)"` ABORTS the whole script. When a test
  deliberately invokes a failing command (e.g. invalid-id status returns rc 1),
  run it as `cmd > tmpfile 2>/dev/null || rc=$?` then read tmpfile — do NOT
  capture via `$(...)` in an assignment, and do NOT use `|| true` (that clobbers
  `$?` so you can't assert the non-zero rc). This cost me one debug cycle.
- **Brace-in-default-param landmine (busybox ash):** `${VAR:-{json...}}` emits an
  EXTRA literal `}` even when VAR is set (the inner `{...}` confuses the `}`
  matching), corrupting JSON. Use `[ -z "$VAR" ] && VAR='{...}'` then print `$VAR`.
- New top-level smoke test `test_jobstate` (alias `jobstate`): stubs the worker
  via a tiny generated CLI whose `$0` IS the stub (because `component_action_async`
  forks `"$0" component_action ...`); controls the worker with `STUB_JSON`/
  `STUB_SLEEP`/`STUB_RC` env; isolates state under `JOBSTUB_DIR`. Registered in
  `all)`, case alias, usage line, and the docker-compose comment.
- Dispatcher (`bin/netshift`): `component_action_async) component_action_async
  "$2" "$3" ;;` and `component_action_status) component_action_status "$2" ;;`
  replaced the old naive `"$0" component_action ... > /tmp/...json &` hack. ACL
  needs NO change (`/usr/bin/netshift` is exec-allowed wholesale).

## task-009: core-switch connectivity self-heal + rollback (anti-brick)

- Root cause of the on-hardware brick: `updates_install_sing_box_stable`
  removed/replaced /usr/bin/sing-box via opkg/apk with NO backup, while the
  kill-switch (nft tproxy + dnsmasq->127.0.0.42->dead sing-box) blocked feed
  access. Binary GONE, no rollback. Extended path already had a tmpfs backup.
- Fix shape (variant B): both install paths are now thin PUBLIC wrappers
  (`updates_install_sing_box_extended`/`_stable`) that run
  `updates_ensure_connectivity <dir>` (preflight; if fail -> selfheal) then call
  the renamed private core (`_updates_install_sing_box_*_core`), then ALWAYS
  `updates_restore_after_swap`. **Epilogue guarantee = single cleanup call**:
  core echoes JSON to a `/tmp/...result.$$` capture file + returns rc; wrapper
  runs restore once, re-emits the JSON, returns rc. No early return skips it (no
  trap needed — the wrapper has exactly one core call).
- `updates_preflight_connectivity <stable|extended>` is direction-aware: stable
  probes `UPDATES_FEED_PROBE_HOST` (downloads.openwrt.org), extended probes
  `UPDATES_GITHUB_PROBE_HOST` (api.github.com). Probe = DNS resolve (dig
  `+short`, nslookup fallback; bind-dig is a dep) AND a curl `-fsSI`/wget
  `--spider` HEAD with `--connect-timeout 5`. No jq/regex.
- `updates_selfheal_connectivity`: (1) backup `/etc/resolv.conf` to tmpfs
  (`UPDATES_RESOLV_BACKUP`), write temp resolver (`UPDATES_HEAL_RESOLVERS`
  1.1.1.1+9.9.9.9) atomically, recheck; (2) if still failing, tear down redirect
  via the EXISTING `/etc/init.d/netshift stop` (dnsmasq_restore + stop_main),
  recheck. Records `UPDATES_HEAL_RESOLV_REPLACED`/`UPDATES_HEAL_REDIRECT_DOWN`
  module-level flags so the epilogue restores EXACTLY what changed (restore
  resolv.conf via mv-back, bring redirect up via `/etc/init.d/netshift start`).
  Reused stop/start so dnsmasq UCI + shutdown_correctly bookkeeping stays right;
  NO hand-rolled nft flush, NO sacred-constant change.
- Stable core gained tmpfs backup/rollback (`updates_stable_rollback`) mirroring
  the extended path: backup binary+libcronet BEFORE package install; restore on
  install-fail OR still-extended validation. CRITICAL ordering: connectivity is
  confirmed (preflight/heal in the wrapper) BEFORE the core touches the binary —
  if heal fails the wrapper aborts and nothing is removed.
- **Testability indirection**: added `UPDATES_SING_BOX_BIN`/`UPDATES_LIBCRONET_LIB`
  constants (default the real /usr/bin/sing-box, /usr/lib/libcronet.so) and used
  them in the STABLE core+rollback only, so the smoke test can point them at
  /tmp mocks without clobbering the container's real binary. Extended path still
  uses the literals (spec said mirror, not refactor).
- New top-level smoke test `test_selfheal` (alias `selfheal`): a generated
  driver sources updater.sh, re-pins RESOLV_CONF/probe-hosts/bin paths, stubs
  dig/nslookup/curl/opkg via a PATH-prepended bin dir whose behaviour is keyed
  off marker files, and installs a fake `/etc/init.d/netshift` that logs
  stop/start/restart (absolute path can't be PATH-overridden — write+restore the
  real one). 5 scenarios: preflight-pass, dns-heal, teardown-heal, heal-fail
  (abort, binary intact), stable-install-fail (backup restored). Registered in
  `all)`, case alias, usage line, docker-compose comment.
- **`set -e` landmine (again)**: the worker returns non-zero on recoverable
  failures (success:false). Calling it directly inside a test under `set -e`
  aborts the WHOLE suite mid-run (only the passes before it print, summary never
  runs, rc=1 with no FAIL line). Wrap the invocation `... || true` — assertions
  read JSON/file-state, not rc. (Distinct from the task-007 `$(...)`-capture
  variant.)

## task-010: keyword filter case-fold is ASCII+Cyrillic (not just ASCII)

- **`ascii_downcase` only folds ASCII A-Z** — Cyrillic server tags (e.g.
  `Германия`) stayed mixed-case, so a Cyrillic include keyword in any other
  case matched 0 nodes → kept=0 → blocked outbound (hardware-confirmed: include
  `[ГеРма,пОЛЬш,рос]` over 316 outbounds gave 0 before, 28 after).
- Fix lives in `sing_box_cf_prepare_subscription_batch`
  (`sing_box_config_facade.sh`). That jq call does NOT `import` helpers.jq, so the
  fold is defined **inline** at the top of the program as `def ucfold:` using only
  `explode`/`map`/`implode` (NO Oniguruma): ASCII `65-90`→`+32`, Cyrillic
  `1040-1071` (А-Я)→`+32`, and the single out-of-block `Ё` `1025`→`1105` (ё).
  Everything else (emoji/other scripts) passes through unchanged → still matches
  as exact codepoint substrings. Replaced the 3 `ascii_downcase` uses (the two
  `$inc`/`$exc` list normalizers + the `$name | ucfold` in the select). The
  `index()`-based `name_passes_keywords` substring logic is unchanged.
- Cyrillic codepoints: А-Я = 1040-1071, а-я = 1072-1103 (so +32), Ё = 1025
  sits BEFORE the block, ё = 1105 sits AFTER it — hence the special-case branch.
- Smoke: extended the existing FBEOF block in `test_subscription` with CASE K
  (Cyrillic). No new top-level test / registration needed — it rides the existing
  `subscription` category. Synthetic names with literal UTF-8 (`Германия`,
  `Орёл`, etc.) in the heredoc are fine; assert via `.count`/`.names`. Used a
  `case "$x" in *Польша*)` membership check rather than exact-name compare for the
  exclude case (order-independent). All ran green in-container.

## task-011: keyword filter must not poison the subscription rejected-hash

- Root cause of the hardware re-download loop: `mark_subscription_outbound_unavailable`
  (`bin/netshift`) md5'd the VALID `<section>.json` and wrote it to `.rejected`
  even when `kept=0` was caused purely by the user's keyword filter (a setting,
  not a bad feed). Then `subscription_cache_is_usable` — which had already passed
  `validate_subscription_file` — still returned 1 on the hash match, forcing a
  re-download; `download_subscription_into_cache` saw tmp_hash==rejected_hash and
  `return 14` (unchanged+rejected) → infinite retry. The poison also survived
  loosening the filter (lived only in `.rejected`).
- Fix A: 2nd arg `keyword_filter_active="${2:-0}"`. When 1: NEVER compute/write
  the hash, `rm -f` the `.rejected` (self-heals a previously poisoned hash), still
  set unavailable state + `subscription_startup_blocked=1`, warn that the FILTER
  (not the feed) emptied the set. When 0: unchanged (genuine outbound-less body
  still recorded → flash-loop guard kept). Caller at the `subscription)` branch
  passes `$subscription_keyword_filter_active` (set 0/1 just above from the two
  UCI keyword lists).
- Fix B: in `subscription_cache_is_usable`, after `validate_subscription_file`,
  run a jq -e "has >=1 proxy outbound" check (same predicate as the batch:
  `[.outbounds[]? | select(.type != "selector" and ... != "block")] | length > 0`,
  NO Oniguruma) → if true `return 0` (usable) regardless of `.rejected`. The
  rejected-hash veto now only fires on a validated-but-outbound-less body. NB:
  `validate_subscription_file` ALREADY requires length>0, so a 0-proxy body fails
  validation first — B is belt-and-suspenders + self-documenting, and robust if
  validation ever loosens. Did NOT touch `download_subscription_into_cache`'s own
  rejected logic (spec: once A/B stop writing+vetoing, a valid body has no
  `.rejected` so return 14 can't fire for it).
- **Testing functions that live in `bin/netshift` (not a lib):** can't source the
  file (it runs the dispatcher + needs LuCI `/lib/functions.sh`). Pattern that
  works: a generated driver that (1) stubs the few helpers the target calls
  (`log`, the `get_subscription_*_path` builders), (2) sources `helpers.sh` for
  the real `validate_subscription_file`, (3) extracts JUST the target functions
  verbatim with awk and `eval`s them:
  `eval "$(awk '/^fname\(\) \{/{p=1} p{print} p&&/^\}/{exit}' "$bin")"`. Relies on
  top-level functions closing with a column-0 `}` and having no nested column-0
  `}` (case/if/while bodies don't). Keeps the test against shipped code, not a copy.
- New top-level smoke test `test_rejected_hash` (alias `rejected`): 6 cases
  (A-no-write+clear, A-recovery, B-not-vetoed, A-protected-no-proxy-still-vetoed,
  regression-usable, A-arg0-genuine-recorded). Registered in `all)`, case alias,
  usage "Available:" line, docker-compose comment. Same name:OK/FAIL parse + the
  subshell-pipe PASS-counter quirk as test_subscription (suite `Results:` total
  omits piped-while passes; the per-test ✓ marks are the source of truth).

## task-012: vmess:// '#fragment' strip before base64 decode

- Root cause: the `vmess)` case in `sing_box_config_facade.sh` passes the RAW
  pre-url_decode link (`$raw_url`, kept that way by task-005 S1 to preserve `+`),
  which STILL carries the `#fragment` (server display name, e.g. `#🇳🇱Ne`).
  `vmess_link_to_json` only did `payload="${url#vmess://}"`, so the `#`/emoji/
  Cyrillic bytes corrupted the base64 → decode failed → fatal. facade:72's
  `url_strip_fragment` only touched the separate `$url`, NOT `$raw_url`, so the
  strip MUST live inside `vmess_link_to_json`.
- Fix (helpers.sh, ONE line): right after `payload="${url#vmess://}"` add
  `payload="${payload%%#*}"` (POSIX longest-`#…`-suffix strip). Safe because the
  base64 body never contains `#`; fragment-less payload = no-op. Existing
  whitespace-strip (`tr -d ' \011\012\015'`, NOT `[:space:]`) + `=` pad loop +
  `base64_decode` run unchanged on the fragment-free payload. Did NOT touch the
  facade / reintroduce url_decode. VMess canonical name still comes from JSON
  `ps`; we only drop the fragment, do not adopt it as the name.
- Smoke: extended the existing vmess facade block in `test_sing_box_config` (`sb`
  category — no new top-level test/registration) with a `vmess-frag-*` case:
  `vmess://<base64(JSON)>#🇳🇱Ne`, sanity-check the link has `#`, then assert
  server/uuid/transport/tls on the generated outbound. The existing ws/tcp/plus
  cases (no `#`) double as the no-fragment regression. shellcheck -S error clean;
  `all` = 76 passed / 0 failed.

## task-013: sing-box-extended version diagnostic (build-suffix strip)

- Root cause: `check_sing_box()` (`bin/netshift`, ~:3276) does
  `version=$(sing-box version | awk '{print $3}')` then `patch=$(... cut -d. -f3)`.
  Extended core prints `1.13.12-extended-2.3.2`, so `patch` became
  `12-extended-2` → non-numeric → `[ "$patch" -ge 4 ]` errors `bad number` →
  `❌ not compatible`. Stock cores have numeric patch so they passed.
- Fix (Variant A′, ONE line + comment): right after the existing
  `version=$(echo "$version" | sed 's/^v//')`, add `version=${version%%-*}`
  (POSIX longest-`-…`-suffix strip; no fork/jq/regex). `1.13.12-extended-2.3.2`
  → `1.13.12`; stock `1.12.0` has no `-` so unchanged; also tolerates future
  `-beta`/`-rc`. `major`/`minor`/`patch` are already `local`; no new vars.
- **OUT-OF-SCOPE PRE-EXISTING BUG (left untouched per spec, but flag it):** the
  comparison chain `if [ "$major" -gt 1 ] || [ "$major" -eq 1 ] && [ "$minor"
  -gt 12 ] || ... && [ "$patch" -ge 4 ]` has wrong precedence — POSIX `[]`
  `&&`/`||` are equal-precedence left-associative, so it evaluates as
  `(...) && [ "$patch" -ge 4 ]`, making the final patch test gate EVERY branch.
  Result: `1.13.12` and even `2.0.0` evaluate to version_ok=0 (only `1.12.x>=4`
  passes). The spec (task-013) explicitly says do NOT rewrite the chain — it
  only fixes the non-numeric `bad number` crash. So the extended diagnostic no
  longer errors, but a TRUE fix of "newer than 1.12.4 ⇒ compatible" needs a
  follow-up task to correct the chain (e.g. parenthesize each branch in a
  single `[ ]` per term or use `sort -V` like `check_requirements` does).
- Smoke: NO new test (pure string strip, no new control flow — per spec). Reran
  `shellcheck -S error` clean on `bin/netshift`; `smoke-tests all` = 76 passed /
  0 failed.

## task-014: route the MAIN DNS server through a proxy outbound (detour)

- The cm/cf DNS primitives ALREADY accept `detour` as the last arg and merge it
  conditionally (`+ (if $detour != "" then {detour:$detour} else {} end)`):
  `sing_box_cf_add_dns_server` $6, `sing_box_cm_add_udp/tls_dns_server` $6,
  `_add_https_dns_server` $8. So an EMPTY detour tag => byte-identical to the
  pre-feature output (proven in smoke via `jq -cS` object compare of the
  empty-tag main server vs a no-detour-arg call). Do NOT touch cm/cf for this.
- New helper `_get_dns_detour_tag()` (bin/netshift, next to
  `_determine_first_outbound_section`/`get_first_outbound_section`) echoes the
  tag or "" = direct. NEVER `exit`; every fallback logs `warn` and degrades to
  direct. Cascade: (1) `dns_via_outbound`!=1 -> "" silent; (2) explicit
  `dns_outbound_section` valid + `section_has_configured_outbound` -> it, else
  warn(if non-empty) + `get_first_outbound_section`; (3) no candidate -> warn+"";
  (4) candidate connection_type block/exclusion -> warn+""; (5)
  `subscription_outbound_is_unavailable` -> warn+"" (self-heal on fresh boot /
  failed sub); (6) else `get_outbound_tag_by_section "$candidate"`. Mirrors
  `get_subscription_download_proxy_address` (toggle + section + fail-safe).
- Wired ONLY into the main `SB_DNS_SERVER_TAG` server in `sing_box_configure_dns`
  (6th arg). Bootstrap (`SB_BOOTSTRAP_SERVER_TAG`) + FakeIP stay direct on
  purpose (chicken-and-egg: bootstrap resolves the DoH/DoT host before the tunnel
  is up; it's also the `domain_resolver` for a hostname main DNS). Two new UCI
  opts documented (commented) in `etc/config/netshift`: `dns_via_outbound`(bool,
  default 0) + `dns_outbound_section`. Read with `config_get_bool`/`config_get`
  + safe defaults — never required live.
- Did Req 4 (low-risk, observable): `check_dns_available` JSON gains
  `"dns_via_outbound_tag"` (via `_get_dns_detour_tag`); `global_check` prints
  `ℹ️ Main DNS via outbound: <tag>` or `ℹ️ Main DNS: direct` (valid-UTF-8 emoji).
- **LuCI `config_get` always returns 0** (assign-and-succeed even when the option
  is unset, leaving the var empty). So step-2's `config_get ... && [ -n "$var" ]`
  detects a non-existent section purely via the EMPTY connection_type, not via rc.
  Test stubs must mimic this (assign-then-`return 0`).
- New top-level smoke test `test_dns_via_outbound` (alias `dnsdetour`): builds
  on/off configs through the real cf/cm path (asserts main-has-detour,
  bootstrap/fakeip no-detour, off no-detour, off byte-parity, both pass live
  `sing-box check`), then awk-extracts `_get_dns_detour_tag` VERBATIM from the bin
  and runs the 8-case cascade table with stubbed UCI + reused helpers. Registered
  in `all)` + case alias + usage "Available:" line + docker-compose comment.
  shellcheck -S error clean on bin + libs + install.sh; `smoke-tests all` = 76
  passed / 0 failed (suite total unchanged because the per-line `pass` runs in a
  piped `while` subshell — same counter quirk as test_subscription; the per-test
  ✓ marks are the source of truth, here 15 green for dnsdetour).

## task-014 (PR#11 backend fixes): nft v6 bracket + dead-code removal

- **nft IPv6 `tproxy ... to` MUST bracket the address** — `tproxy ip6 to
  "$ADDR_V6:$PORT_V6"` expands to `::1:1603`, which nftables v1.1.3 parses as a
  BARE IPv6 address (`[::0.1.22.3]`, port 1603 read as 0x1603 hextet) with NO
  port. `nft -c` PASSES and `sing-box check` is unrelated — neither gate catches
  it; only on-device IPv6 breaks. Fix: `tproxy ip6 to "[$ADDR_V6]:$PORT_V6"`.
  Verify with the no-root trick: write the rule to /tmp/t.nft and
  `unshare -rn sh -c 'nft -f /tmp/t.nft && nft list ruleset' | grep tproxy` —
  bracketed form normalizes to `tproxy ip6 to [::1]:1603` (correct). The IPv4
  `tproxy ip to "$ADDR:$PORT"` is fine (IPv4 has no `:` ambiguity). sing-box
  inbounds (`sing_box_cm_add_*_inbound` address+port as SEPARATE jq args ->
  JSON `listen`/`listen_port`) have NO bracket defect — don't "fix" them.
- **Router-originated traffic is DIRECT by design** (operator decision A). The
  PR's model marks only LAN/forwarded traffic in `mangle` (prerouting) and
  splits proxy/direct in sing-box; `mangle_output` only carries local/loopback
  daddr returns + the `NFT_OUTBOUND_MARK` return (so sing-box-originated packets
  don't loop back into tproxy). Documented with a comment; no behavior change.
- **The `@netshift_subnets` (`NFT_COMMON_SET_NAME`) nft set was fully dead** —
  created + populated at 6 sites but matched by NO nft rule after PR#11. SAFE to
  remove because every subnet source is independently carried into a sing-box
  rule_set: user_subnets -> `patch_source_ruleset_rules ip_cidr` + local source
  ruleset; local_subnet_lists -> `import_plain_subnet_list_to_local_source_ruleset_chunked`;
  community_lists -> `configure_community_list_handler` (`$SRS_MAIN_URL/<svc>.srs`
  remote ruleset); remote json/srs subnets -> `configure_remote_domain_or_subnet_list_handler`
  (`sing_box_cm_add_remote_ruleset`); remote plain -> `prepare_source_ruleset` +
  plain import. DISCORD is the ONE exception that still needs an nft set
  (`NFT_DISCORD_SET_NAME`) — it has a live dport-restricted mangle rule
  (`@netshift_discord_subnets udp dport {19000-20000,50000-65535}`) that a
  sing-box route rule can't express. Removed: set creation (~972), all 6
  `nft_add_set_elements*` populate calls, the now-orphaned
  `import_subnets_from_remote_json_file`/`_srs_file` (json/srs now log
  "sing-box manages updates" like the domains path), `netshift_subnets` from the
  diagnostics `sets` list, and the `NFT_COMMON_SET_NAME` constant. Left the 9
  IPv4 `SUBNETS_*` constants (only `SUBNETS_DISCORD` used) in place — constants.sh
  is `# shellcheck disable=SC2034` so unused-looking vars don't fail lint, and
  trimming them was out of declared scope.
- **8 `SUBNETS_*_V6` constants had zero consumers** (`git grep` only matched
  definitions + a memory doc) — removed.
- **B-09 dead predicates**: `is_ip`/`is_ipv6_cidr`/`is_ipv6` in helpers.sh were
  all unused (`is_ipv6` only called by the other two; tests use only `is_ipv4`/
  `url_is_ipv6_literal`/`is_ipv4_ip_or_ipv4_cidr`). Removed all three.
- **Monitor spawn guard (B-05)**: extracted `start_sing_box_monitor` mirroring
  the `start_subscription_startup_retry_worker` pidfile-guard — if
  `/var/run/netshift_monitor.pid` exists and `kill -0 "$pid"` succeeds, skip the
  spawn (else `rm` stale pidfile then spawn). Prevents a procd double-start from
  orphaning a monitor that `stop()` can no longer kill.
- **B-08 dnsmasq guard (review-001 FIX — sentinel, not markers)**: my first B-08
  attempt gated `dnsmasq_is_configured_for_netshift` on the presence of a private
  backup marker (`netshift_server`/`netshift_noresolv`/`netshift_cachesize`).
  That was WRONG and regressed STOCK dnsmasq: on a default box with no original
  server/noresolv/cachesize, `dnsmasq_configure` writes NO markers
  (`backup_dnsmasq_config_option` only writes when the original value is
  non-empty; the server-backup loop is skipped when current servers are empty).
  So the guard returned false, and the redundant `dnsmasq_configure force` path
  (monitor recovery restart, double-start) re-ran "backup" — but the LIVE values
  were now netshift's OWN (noresolv=1, cachesize=0), so it captured those as the
  backup -> `dnsmasq_restore` later restored 1/0 instead of the OpenWRT defaults
  (0/150) -> router DNS broken after stop/uninstall.
  CORRECT fix = an explicit netshift-owned SENTINEL: `dnsmasq_configure` does
  `uci_set "dhcp" "@dnsmasq[0]" "netshift_configured" 1` UNCONDITIONALLY right
  after applying our config (before the commit); `dnsmasq_is_configured_for_netshift`
  short-circuits iff `netshift_configured == 1` (authoritative ownership flag, no
  value/marker inference); `dnsmasq_restore` clears it with `uci_remove_quiet`
  before its commit so a fresh future configure re-establishes ownership. The
  sentinel is a distinct option name (not in the `server` list), so it never
  leaks into the server/backup iteration. Verified all 3 scenarios via an
  awk-extracted-functions harness (use an EXACT-match UCI stub — `awk -F'\t'
  $1==k`, NOT grep/sed, because the literal `@dnsmasq[0]` key contains `[0]`
  which a regex reads as a char class and silently mis-reads every lookup):
  (A) stock -> sentinel set, no spurious backup, force-again short-circuits,
  restore=0/150, sentinel cleared; (B) admin-had-config -> real values backed up
  & restored intact; (C) coincidental admin match w/o sentinel -> NOT treated as
  owned. shellcheck clean; smoke 81/0.
- shellcheck -S error clean (bin + libs + install.sh); `smoke-tests all` = 81
  passed / 0 failed (unchanged baseline). No new smoke test (separate packaging
  task owns nft/v6 coverage per spec). No sacred constant VALUES changed.

## task-017: Component Manager backend (stock latest, NetShift self-update)

- **Two new component_action() cases** (`updater.sh` ~:1612): `sing_box:
  check_update_stable) updates_check_sing_box_stable` (SYNC) and
  `netshift:self_update) updates_self_update_netshift` (async via the existing
  `component_action_async`). NO dispatcher (bin/netshift) change — both are
  sub-cases of the already-routed `component_action`; `component_action_async`/
  `_status` are component-agnostic. NO ACL change.
- **pkg-manager abstraction re-implemented locally** (updater.sh does NOT source
  install.sh): `updates_pkg_is_apk` (`command -v apk`), `updates_pkg_install_file`
  (apk add --allow-untrusted / opkg install, `</dev/null` non-interactive),
  `updates_pkg_is_installed` (apk/opkg list grep), `updates_pkg_candidate_version`
  (FEED version). Candidate parse, busybox-safe, NO Oniguruma: opkg `list <pkg>`
  → `"<name> - <ver>"`, `awk -F' - ' '{print $2}'`; apk `list <pkg>` → first
  token `<name>-<ver>`, strip `"<pkg>-"` prefix via `${line#"$pkg"-}`.
- **Stock check `updates_check_sing_box_stable`**: mirrors the extended-check JSON
  shape. Runs `opkg/apk update` best-effort first (`|| true`). status: candidate
  empty → `success:false` (feed unreachable, return 1); sing-box absent
  (`command -v`) → `not_installed`; else compare on LEADING semver `${v%%-*}`
  (drops `-r1`/`-extended-…`) via `is_min_package_version` (sort -V) →
  `latest`/`outdated`. NEVER exits. STABLE JSON: `{success,current_version,
  latest_version,status:"latest"|"outdated"|"not_installed"}`.
- **NetShift self-update = Variant A** (targeted pkg upgrade, NOT install.sh).
  `updates_self_update_netshift` (public wrapper) COPIES the
  `updates_install_sing_box_extended` epilogue EXACTLY: reset UPDATES_HEAL_*,
  `updates_ensure_connectivity "extended"` (GitHub dir) else restore+fail JSON,
  run `_updates_self_update_netshift_core >"$out"`, capture rc+json, rm, ALWAYS
  `updates_restore_after_swap`, re-emit, `return $rc`. Single cleanup path; no
  trap. Core is NON-interactive, all `local`, NEVER `exit`: idempotent guard
  (`${installed#v}` == `${latest#v}` → "Already up to date"); minimal
  `/etc/config/netshift` tmpfs backup; download assets matching pkg-name prefixes
  (`netshift`,`luci-app-netshift`, RU i18n ONLY if `updates_pkg_is_installed`)
  filtered to `.ipk`/`.apk` by pkg-mgr via `grep -o 'https://[^"[:space:]]*\.ext'`
  (mirrors install.sh:269-274, busybox-safe); install core→luci→ru; core-install
  fail is fatal-to-the-op (success:false + restore config), luci/ru fail is
  non-critical (warn+continue); defensive config restore if live file empty.
- **Self-replacement CONFIRMED safe**: the `netshift` pkg overwrites
  `/usr/bin/netshift` (this very script). busybox ash reads the whole script into
  memory before pkg_install; the async fork (`( trap '' HUP; "$0" component_action
  netshift self_update >out; updates_write_finished_job_state ... )`) + the
  finished-state write complete from memory. The self-update core has ZERO live
  re-exec after install: NO `updates_restart_netshift`, NO `"$0"`, NO `exec`, NO
  direct `/usr/bin/netshift` or `/etc/init.d/netshift` call. (Only path that runs
  the init script is `updates_restore_after_swap`'s `/etc/init.d/netshift start`,
  which fires ONLY if the heal tore the redirect down, AFTER install completes,
  as a fresh subprocess that safely loads the on-disk binary.) UI (task-018)
  reloads the page after success. Verified via `grep` of the core's line range.
- **New constants** (constants.sh, NO ports/marks): `NETSHIFT_RELEASE_API_URL`
  (= install.sh REPO / get_system_info :3347 endpoint),
  `UPDATES_NETSHIFT_DOWNLOAD_DIR=/tmp/netshift/selfupdate`,
  `UPDATES_NETSHIFT_CONFIG_BACKUP=/tmp/netshift/config.bak`,
  `UPDATES_NETSHIFT_PKG_CORE/LUCI/I18N_RU`. `get_system_info` UNCHANGED (UI gets
  versions there; stock check is a separate action — no missing field).
- **Subshell-piped `while read url` loop can't set parent vars** (task-007
  variant): `_updates_self_update_download_assets` re-checks the dir
  (`ls "$dir/netshift"*`) AFTER the loop to decide success, not a flag set inside.
- **Smoke tests `test_check_update_stable` (alias `stablecheck`, 4 cases) +
  `test_self_update_netshift` (alias `selfupdate`, 13 assertions)**. Both source
  the REAL updater.sh + helpers.sh, re-pin paths/constants, stub via markers.
  `test_check_update_stable` KEY GOTCHA: `command -v sing-box` finds the real
  `/usr/bin/sing-box`; to test `not_installed` I built an ISOLATED PATH dir of
  symlinks to just the needed coreutils (NO /usr/bin in PATH) and linked the fake
  sing-box in/out per scenario. `test_self_update_netshift` overrides
  `updates_http_get_once` (GitHub JSON) + `updates_download_to_file` in the driver
  + stubs opkg `install`/`list-installed` (logs installs) + fake `/etc/init.d/
  netshift` (absolute write+restore). Registered all 5 points (all)/case/usage/
  compose). Used task-009 `... || true` set -e guard. shellcheck -S error clean;
  `smoke-tests all` = 101 passed / 0 failed (was 84 baseline; +17 new).
