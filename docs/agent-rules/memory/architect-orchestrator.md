# Memory — architect-orchestrator

Durable project knowledge for designing and decomposing NetShift tasks.
Read this before planning. Append new durable findings; keep under ~200 lines.

## Project shape (verified)

- NetShift = OpenWRT 24.10+ traffic router on top of **sing-box** (>=1.12.0,
  jq>=1.7.1). Fork of `itdoginfo/podkop`, rebranded to NetShift at 0.8.0. Beta.
  GPL-2.0-or-later + separate restrictive trademark policy (`TRADEMARK.md`).
- Three packages, one-way dependency chain:
  `luci-app-netshift` (LuCI UI, hand-written `.js` views + generated `main.js`)
  -> `fe-app-netshift` (TypeScript source of `main.js`, built by tsup)
  -> `netshift` (POSIX ash + jq backend) -> sing-box / nftables / dnsmasq.
  The UI talks to the backend ONLY via LuCI `fs.exec` of `/usr/bin/netshift`
  and `/etc/init.d/netshift` (ACL-gated), plus Clash API on :9090.

## Sacred runtime contract (constants.sh — never change casually)

- TProxy inbound `127.0.0.1:1602`; DNS inbound `127.0.0.42:53`; Clash API `:9090`.
- FakeIP range `198.18.0.0/15`. Marks: FakeIP `0x00100000`, outbound `0x00200000`.
- nft table `NetShiftTable` (inet); routing table `105 netshift`.
- Required versions `SB_REQUIRED_VERSION=1.12.0`, `JQ_REQUIRED_VERSION=1.7.1`.

## Data flow (start_main in usr/bin/netshift)

check_requirements -> migration (currently no-op) -> validate services ->
br_netfilter_disable -> NTP sync -> subscription cache prep -> route table + nft
base -> sing_box_configure_service -> sing_box_init_config (build JSON) ->
save+`sing-box check` -> cron jobs -> start sing-box -> dnsmasq_configure ->
`list_update &` (background heavy list download).

## Quality gates a task must pass before "done"

- Backend (`netshift/files/**`): `shellcheck` skill (severity error) +
  `smoke-tests` skill (tests/entrypoint.sh `all`).
- Frontend (`fe-app-netshift/**`): `frontend-ci` skill (`yarn ci`) AND the
  committed `main.js` must be regenerated (build must leave no git diff).
- Packaging/CI changes: smoke-tests at minimum; verify both ipk and apk paths.

## Decomposition policy

- Map subtasks to the right developer agent:
  backend/shell/jq/sing-box/nft/dnsmasq/UCI -> `shell-backend-developer`;
  TS source / LuCI views / validators / i18n -> `luci-frontend-developer`;
  Makefile / Docker / SDK / workflows / tests harness / install.sh ->
  `packaging-ci-engineer`.
- A change touching the TS source almost always also requires a rebuild of
  `main.js` (frontend dev handles via `yarn build`). Flag this in the spec.
- "System-level" changes (nft, routing, config schema, ports/marks, dnsmasq,
  packaging) must be verified across the whole chain, not one file.
- Never allow a commit without a passed code-reviewer verdict. Never skip the
  relevant gate. Humans commit manually — agents never auto-commit.

## Known latent bugs / landmines (don't reintroduce; fix only if in scope)

- `usr/bin/netshift` dispatches `main)` and `check_sing_box_logs)` but NO such
  functions are defined — dead/broken dispatch.
- nft proxy chain hardcodes `127.0.0.1:1602` instead of using the constants
  (duplication; changing the constant won't change the rule).
- VPN `domain_resolver` uses `$dns_server` (undefined in scope) instead of
  `$domain_resolver_dns_server`.
- Frontend `runFakeIPCheck` has inverted-looking allGood/atLeastOneGood logic.
- Diagnostic strings contain intentional CP1251 mojibake (emoji/box-drawing) —
  preserve byte sequences when editing.
- `validate_subscription_file` (helpers.sh) only checks `.type` is NOT in
  {selector,urltest,direct,dns,block}. A body whose outbounds lack `.type`
  entirely (e.g. a single Xray-config OBJECT using `.protocol`) passes as
  "valid" → bypasses the fallback normalizer and later fails `sing-box check`.
  An Xray ARRAY is `type=="array"` and correctly falls through to normalize.
  Watch this when adding any pre-normalize validate gate.

## Subscription pipeline facts (verified 2026-06)

- Fallback chain in `download_subscription_into_cache` (usr/bin/netshift):
  validate raw body FIRST, only then `normalize_subscription_to_singbox`
  (base64 / plaintext URI list / Xray-JSON). UA fallback wraps the whole loop:
  it probes `SUBSCRIPTION_USER_AGENT_CANDIDATES` (constants.sh) when no UA is
  configured, caches the winner in `<section>.user_agent` (atomic .tmp.$$+mv).
- New per-section UCI option `subscription_user_agent` is read but NOT yet in
  the UCI schema / LuCI / ACL. Degrades gracefully (empty ⇒ auto). Treat any
  promotion to a real UI knob as a system-level change (schema + LuCI + i18n).
- `xray_json_to_uri_lines` converts Xray client configs (object|array) to share
  URIs; emits ONLY keys the facade reads (type/path/host/mode/serviceName/
  security/sni/alpn/fp/pbk/sid/flow); drops vmess (counted by
  `xray_json_count_unsupported`) and dialerProxy-chained outbounds; dedups on
  the connection part. No-regex jq + busybox-safe sed pre-gate.

## Core-switch (sing-box <-> extended) failure — DIAGNOSED on real hardware 2026-06

- SYMPTOM: switching stock->extended fails; on the router the new ~79MB binary
  sits at /usr/bin/sing-box but with perms `rw-------` (NOT executable), the
  tmpfs backup + downloaded archive remain, sing-box won't run.
- ROOT CAUSE: **rpcd timeout**. rpcd runs with `-t 30` (30s). The UI calls
  `component_action sing_box install_extended` SYNCHRONOUSLY via LuCI fs.exec.
  Download (~29MB over a slow/proxied link) + gzip extract of the 50MB binary
  (measured **13s just for extract** on aarch64 cortex-a53) exceeds 30s, so rpcd
  KILLS the process mid-flight — AFTER `tar -O > /usr/bin/sing-box` (file written
  `rw-------` under the context umask 0077) but BEFORE `chmod 0755` + the
  `LD_LIBRARY_PATH=/usr/lib sing-box version` validation. Hence the un-chmod'd
  binary, leftover backup/archive, no cleanup.
- DISPROVEN earlier guesses: (a) NOT a disk-space issue (repro'd with free
  space). (b) NOT the missing-LD_LIBRARY_PATH theory — the extended binary runs
  `sing-box version` fine WITHOUT LD_LIBRARY_PATH (libcronet only needed at
  runtime for naive); `chmod 0755` itself works under umask 0077. The code's
  chmod/validate is correct; it just never gets to run.
- FIX DIRECTION (matches podkop-plus): make core-switch ASYNCHRONOUS — podkop-plus
  has `component_action_async` (writes output to a file, forks the work) +
  `component_action_status` (UI polls). NetShift's updater is synchronous and has
  no async/status path. Port that model: fork the install, return immediately,
  poll status; UI shows progress instead of hitting the 30s rpcd wall.
- Secondary hardening to fold in: chmod 0755 BEFORE validation is already there
  but ordering/robustness should survive interruption; also rulesets in
  /tmp/sing-box/rulesets were `rw-------` (umask 0077) — sing-box could still read
  them as root, not the failure cause, but worth normalizing.
- Manual recovery that works: `chmod 0755 /usr/bin/sing-box` (the downloaded
  extended binary is valid), `rm -rf /tmp/netshift-sbext.*`, restart netshift.
- Router access for testing: `ssh root@192.168.1.1` (no password). aarch64,
  OpenWrt 24.10.5, overlay 60.9M (16.5M free), /tmp tmpfs 117M. scp does NOT work
  (no sftp-server) — push scripts via `echo <base64> | base64 -d > f` over ssh.

## Core-switch async fix (task-007) — on-device verified 2026-06; SECOND bug found

- task-007 async model WORKS on real hardware: `component_action_async` returns
  in 0s with a job_id (no more rpcd 30s kill), `component_action_status` polling
  goes running->finished cleanly. The PRIMARY bug (synchronous timeout) is fixed.
- BUT live-testing exposed a SECOND, deeper bug in `updates_install_sing_box_stable`
  (extended->stock): it has NO backup/rollback (unlike the extended path) AND the
  whole switch happens while NetShift's nft tproxy + dnsmasq redirect are STILL
  active. Sequence that bricked the router:
  1. install_stable removes/replaces the extended binary, then `opkg/apk install
     sing-box` needs working internet — but the only internet was THROUGH the now
     -dead VPN. opkg fails with "Operation not permitted" + DNS timeout (the nft
     kill-switch sends marked traffic to a dead sing-box).
  2. Net result: /usr/bin/sing-box GONE, no rollback, router has no working core
     and can't fetch one (extended path also fails: GitHub unreachable w/o VPN).
- This is a CLASSIC kill-switch deadlock: you can't download a new core because
  the old core (that provided connectivity) is gone.
- RESCUE that works: `/etc/init.d/netshift stop` (tears down nft/dnsmasq so direct
  internet returns) -> set a real resolver -> `opkg update && opkg install
  sing-box` -> `/etc/init.d/netshift restart`. Verified: restored stock 1.12.22,
  sing-box running.
- DESIGN IMPLICATION for the stable-rollback path (future task): before
  install_stable, KEEP a backup of the current (extended) binary on tmpfs and
  RESTORE it if the package install fails (so a failed downgrade never leaves the
  router core-less) — mirror the extended path's backup/restore. Also consider
  tearing down the redirect (or a temporary direct route) during a core swap so
  the package manager can reach the feeds. The extended->stock path fundamentally
  needs connectivity that the dead VPN may have been providing.
- Router note: stock sing-box install also drops `/etc/config/sing-box-opkg` and
  `/etc/sing-box/config.json-opkg` (conffile conflicts) — harmless, NetShift owns
  its own config path.

## sing-box-extended capability map (researched 2026-06)

- NetShift ALREADY installs sing-box-extended: `updater.sh` pulls
  `shtorm-7/sing-box-extended`; `is_sing_box_extended` gates features (today only
  xhttp transport in the facade). So the runtime platform for extended protocols
  exists; what's missing is config GENERATION (jq cm_*/cf_*), UCI schema, UI.
- Our facade currently builds only: socks4/4a/5, vless, ss, trojan, hysteria2.
  Transports: ws, grpc, httpupgrade, xhttp. No endpoint/wireguard support at all
  (`sing_box_cm_add_*_outbound` has no wireguard/endpoint).
- Extended (repo `sing-box-extended-extended/option/*.go`) adds many: anytls,
  tuic, shadowtls, wireguard(+Amnezia/AWG), warp(+Amnezia), masque, mieru,
  mtproxy, naive, openvpn, ssh, tor, trusttunnel, sudoku, bond, failover, vpn,
  vmess; transports incl. v2ray kcp/quic, simple-obfs, sip003.
- Amnezia WG schema (sing-box 1.12 `endpoint` model): an `endpoint` with
  `"type":"wireguard"`, `private_key`, `address` (listable prefix), `peers[]`
  (address/port/public_key/pre_shared_key/allowed_ips/persistent_keepalive...),
  plus nested `"amnezia": { jc,jmin,jmax,s1..s4, h1..h4 (ranges), i1..i5, j1..j3,
  itime }`. WARP = same WG core + `amnezia` + Cloudflare `profile`/`reserved`.
- Feasibility tiers for porting to our ash+jq backend:
  * EASY (pure-JSON outbound, no extra daemon, just a new cm_* + cf_* + URI/UCI
    parse): tuic, anytls, shadowtls, vmess, naive, hysteria(v1). These mirror the
    existing vless/trojan/hysteria2 pattern.
  * MEDIUM: wireguard + Amnezia/AWG and WARP — needs the `endpoints[]` array
    (new section in config skeleton, route ties to endpoint tag) + key/peer
    parsing; input format must be decided (awg:// vs wg-conf vs UCI fields).
  * HARD / likely out of scope: openvpn, mieru, masque, mtproxy(outbound),
    trusttunnel, sudoku, tor, ssh, bond/failover/vpn groups — bespoke schemas,
    some need extra config files/daemons; high test surface.
- Hard dependency for ANY of these: the user must be running the extended build;
  gate generation behind `is_sing_box_extended` and fail safe (warn + skip) when
  stock sing-box is installed, exactly like xhttp does today.

## sing-box-extended version diagnostic (task-013 — done 2026-06-05)

- BUG: `check_sing_box` (usr/bin/netshift ~3276) showed "❌ version not compatible"
  on the extended core. TWO coupled defects:
  1. `awk '{print $3}'` on `sing-box version 1.13.12-extended-2.3.2` → patch via
     `cut -d. -f3` = `12-extended-2` (non-numeric) → `[: bad number`.
  2. The compare `if [ A ] || [ B ] && [ C ] || [ D ] && [ E ] && [ F ]` was
     UNGROUPED. POSIX `&&`/`||` are EQUAL-precedence, LEFT-associative, so it
     parses `(((((A||B)&&C)||D)&&E)&&F)` — the trailing E/F gate EVERY branch,
     so 1.13.x AND 2.0.0 evaluate as not-compatible even with a numeric patch.
- FIX (Variant 2, operator-chosen): strip suffix `version=${version%%-*}` (gives
  honest semver; extended author only bumps the trailing `-extended-X.Y.Z`,
  leading major.minor.patch is true upstream sing-box) + regroup each AND-term in
  `{ ...; }`. Kept threshold 1.12.4 + printed text. Did NOT touch check_requirements
  (uses sort -V, already extended-safe). 1-file change, gates green.
- LANDMINE for future tasks: any `[ ] || [ ] && [ ]` chain in this repo without
  `{ ...; }` grouping is suspect — equal precedence means trailing AND-terms leak
  into prior OR-branches. Group every AND-term. (My first decomposition wrongly
  assumed the strip alone fixed it; the dev caught the precedence bug on live
  reasoning — TRUST dev "second defect" flags, re-derive the truth table myself.)
- Extended core real output (operator hardware, captured for the epic): version
  `1.13.12-extended-2.3.2`, Tags include `with_quic,with_wireguard,with_utls,
  with_masque,with_mtproxy,with_openvpn,with_trusttunnel,with_sudoku,
  with_naive_outbound,with_gvisor`. So the shtorm-7 build SHIPS the build-tags for
  nearly all of epic Tiers 1–3 (tuic/hysteria need with_quic ✅, AWG needs
  with_wireguard ✅, sudoku/trusttunnel/openvpn ✅) — CX-4 build-tag uncertainty is
  largely resolved EMPIRICALLY for this build; still gate generation behind
  is_sing_box_extended + tolerate a per-protocol `sing-box check` rejection.
- SECOND hardcode of the version threshold confirmed: check_sing_box hardcodes
  "1.12.4" (major/minor/patch literals + text) while SB_REQUIRED_VERSION=1.12.0 in
  constants.sh. Known rassinkhron; left as-is per operator (out of task-013 scope).

## Subscription keyword filter — Cyrillic case bug (task-010, found on hardware 2026-06)

- REAL bug (not version skew): the keyword filter's "case-insensitive" claim only
  holds for ASCII. `sing_box_cf_prepare_subscription_batch`
  (sing_box_config_facade.sh:542/543/567) uses jq `ascii_downcase`, which does
  NOT lowercase Cyrillic (or any non-ASCII).
- FIX: replace the 3 `ascii_downcase` in prepare_subscription_batch with an inline
  jq `def ucfold` (codepoint arithmetic, NO Oniguruma): ASCII A-Z (65–90)+32,
  Cyrillic А-Я (1040–1071)+32, Ё(1025)->ё(1105). Apply to BOTH the keyword list
  and the node name. `explode`/`map`/`implode`/`index` all work on the device jq.
  (Это inline — этот jq-вызов НЕ импортирует helpers.jq.)
- rejected-hash (`<section>.rejected`, md5 of body) can wedge a retry storm if a
  STUB body once got cached as rejected; it self-clears once a real body downloads
  (return 0 path rm's it). Not the root cause here but amplified the symptom.

## Workflow facts

- Contribution gating: `CODEOWNERS=@yandexru45`; PRs accepted only after Telegram
  coordination with authors (README). Reflect this in `/describe` output.
- **Frontend yarn trap (verified 2026-06):** repo `fe-app-netshift/yarn.lock` is
  CLASSIC yarn v1 format; there is NO `packageManager` pin and NO `.yarnrc.yml`.
  A local corepack yarn 4.x will try to MIGRATE on `yarn install`, polluting the
  tree with a 3000+ line `yarn.lock` rewrite + untracked `.yarn/` and
  `.yarnrc.yml`. These are NOT deliverables — discard before commit
  (`git checkout -- fe-app-netshift/yarn.lock`; rm `.yarn/`/`.yarnrc.yml`). To
  verify the gate independently without polluting, run the tools directly from
  `node_modules/.bin` (prettier/eslint/vitest/tsup) instead of `yarn install`.
  Tell frontend devs to leave yarn.lock alone.
- The frontend-ci `main.js` no-diff check: a TYPE-ONLY change in TS source
  (e.g. adding optional fields to a `types.ts` interface) produces NO main.js
  diff — that is expected/correct, not a missed rebuild.

## Subscription keyword filter (issue #5, task-002/003 — done 2026-06)

- Backend filter lives in `sing_box_cf_prepare_subscription_batch`
  (sing_box_config_facade.sh): one jq pass between candidate-select and the
  static-unsupported filter, BEFORE tag dedup + sing-box check. Covers native +
  all fallback (base64/URI/Xray) bodies and both selector branches automatically.
- UCI options (cross-layer contract, verbatim): `subscription_filter_include_keywords`
  (whitelist) / `subscription_filter_exclude_keywords` (blacklist), both UCI
  `list`. Read in the `subscription)` branch via `config_list_foreach`.
- Semantics: include=OR (empty⇒keep all), exclude=OR(drop), SUBSTRING,
  ASCII-case-insensitive (`ascii_downcase`), byte-exact for emoji/Cyrillic.
  jq: NOTE `include`/`exclude` are RESERVED jq words — devs used `$inc`/`$exc`;
  matching must use `. as $kw` inside any/all to avoid the `.`-after-pipe rebind.
- Empty-after-filter ⇒ existing fail-safe `mark_subscription_outbound_unavailable`
  + warn (NO exit 1). `skipped` stays "statically unsupported" (compute `$total`
  AFTER the keyword filter, not before).
- UI: two `form.DynamicList` in `section.js` after `subscription_group_by_countries`,
  rmempty=true, NO validator (keep emoji/space verbatim); `string[]?` fields on
  `ConfigProxySubscriptionSection` in types.ts; ru/en via locale tooling.

## PR review workflow + PR #11 findings (review-001, 2026-06-06)

- Reviewing an external PR (no `gh` CLI installed): fetch via API
  `curl https://api.github.com/repos/yandexru45/netshift/pulls/N` (meta),
  `.../files` (per-file stats), and `-H "Accept: application/vnd.github.v3.diff"`
  for the raw diff. Then `git fetch origin pull/N/head:pr-N` to get a local ref
  diffable vs `main`. Workspace `.pr-review/` + `*.txt` are gitignored (untracked).
- Decompose review by LAYER (backend / frontend+i18n / tests-packaging) into
  separate diff txt files; launch one `explore` subagent per layer IN PARALLEL
  (layers don't share files), then consolidate with the formal `code-reviewer`.
  Give each subagent an architect "systemic notes" file of HYPOTHESES to verify.
- **nftables landmine (VERIFIED on nft v1.1.3):** `tproxy ip6 to <addr>:<port>`
  REQUIRES bracketed `[addr]:port`. The unbracketed form (e.g. `::1:1603`) PASSES
  `nft -c` AND `sing-box check`, but nft normalizes it to a BARE address with NO
  port (`::1:1603` -> `[::0.1.22.3]`). Only on-device / `unshare -rn nft -f` +
  `nft list ruleset` reveals it. IPv4 `addr:port` is fine unbracketed; v6 is not.
- **Local nft verification trick (no root):** `unshare -rn nft -c -f file` /
  `unshare -rn sh -c 'nft -f f && nft list ruleset'` gives netlink in a private
  netns so you can load+inspect normalized rules. Plain `nft -c` fails with
  "cache initialization failed: Operation not permitted" without it.
- PR #11 ("Синхронизация с netshift", spgsroot, +2314/-1364, 23 files) verdict:
  **REQUIRES CHANGES**. Doc at `.pr-review/REVIEW-pr-11.md` (canonical copy would
  be `docs/tasks/sync-netshift-review-001.md`). Headline = IPv6 + DoH-block +
  global_proxy + sing-box health monitor + check_proxy rework.
  * BLOCKER B-01: unbracketed v6 tproxy rule (above).
  * Majors: nft model shift (mangle now marks ALL interface traffic, split moved
    to sing-box route rules) — `mangle_output` lost router-originated @common/
    fakeip marking (regression); `@netshift_subnets`/@common still populated each
    `list_update` but matched by NO rule (dead import path); 8x `SUBNETS_*_V6`
    dead constants; `start()` spawns `monitor_sing_box` with no pidfile+kill-0
    guard (orphan leak); over-permissive `validateIPV6` regex (accepts `:::`,
    `1::2::3`, etc.) shared by subnet+dns validators, no negative tests; 3 new
    flag descriptions concat'd inside `_()` -> ship untranslated.
  * GOOD: generated `main.js` is a faithful DRIFT-FREE rebuild (CI no-diff should
    pass); NO Oniguruma jq; UTF-8 emoji intact; i18n catalogs machine-consistent.
  * Coverage gap: the nft model shift has NO smoke test (test_global_proxy only
    checks sing-box route-rule SHAPE; test_nft byte-identical to base) — that's
    why B-01 slipped. Any nft-rule PR should add an `nft list ruleset` assertion.

## PR #11 fix-to-perfect cycle (2026-06-06, after operator merged the PR)

- Operator merged PR #11 to main, then asked to fix everything to perfection.
  Decomposed the review-doc issues into 3 task specs (docs/tasks/task-014 backend,
  -015 frontend, -016 packaging) + delegated to the 3 dev subagents, ran the
  dev<->code-reviewer loop per layer until all APPROVED. NOTE: `docs/tasks/` is
  gitignored (line 7 `docs/tasks`), so task specs are session artifacts (like
  .pr-review/), not committed — that's by project design (only TEMPLATE-*.md are
  force-tracked).
- Operator design decisions for the nft model shift: B-02=A (router-originated
  traffic stays DIRECT in the new mark-everything-in-prerouting model; document
  only, don't restore mangle_output marking) and B-03/B-04=A (remove the dead
  @netshift_subnets populate path + dead SUBNETS_*_V6). Rule: dead-code removal
  for a SET requires first PROVING every populated source is carried by a sing-box
  rule_set; the dev produced a coverage map (community->$SRS_MAIN_URL/<svc>.srs,
  user/local/remote subnets->rule_sets). DISCORD set is RETAINED (it has a
  dport-restricted mangle rule `udp dport {19000-20000,50000-65535}` that a
  sing-box route rule cannot express). M1/M2 left as non-blocking follow-ups
  (orphaned rulesets.sh helpers + unused IPv4 SUBNETS_* under SC2034).
- **dnsmasq "we-own-it" guard landmine (B-08):** a guard that infers netshift
  ownership from the PRESENCE of `netshift_*` BACKUP markers is WRONG, because
  `backup_dnsmasq_config_option` only writes a marker when the ORIGINAL value was
  non-empty. On stock/default dnsmasq (empty server/noresolv/cachesize) NO markers
  exist, so on the redundant `dnsmasq_configure force` path (monitor recovery /
  double-start) the guard flips false, re-runs backup, and records netshift's OWN
  live values (noresolv=1/cachesize=0) as the "backup" -> restore later sets
  noresolv=1/cachesize=0 instead of defaults 0/150 -> router DNS broken after stop.
  FIX: an explicit unconditional sentinel `netshift_configured=1` set in
  dnsmasq_configure, gating the short-circuit, cleared in dnsmasq_restore.
- **nft v6 NEGATIVE-guard test landmine:** the buggy unbracketed `::1:1603`
  normalizes DIFFERENTLY per nft build: `[::0.1.22.3]` on nftables v1.1.3 (WSL),
  but `[::1:1603]` on OpenWRT 24.10.6's nft (the smoke container). So a negative
  grep for `::0` OR even `\[::0` is a DEAD always-passing assertion in the smoke
  env. ROBUST pattern: `grep 'tproxy ip6 to \[' | grep -qv '\[::1\]:1603'` (any
  bracketed dest that ISN'T the correct one). Always self-prove a regression guard
  by temporarily reintroducing the bug and confirming the test FAILS.
- Environment (WSL2 Debian 12): Docker daemon socket-activation can leave a
  self-referential symlink (`/var/run/docker.sock -> /run/docker.sock` where
  /var/run IS /run); fix = `sudo rm -f /run/docker.sock; sudo systemctl restart
  docker.socket docker.service`. shellcheck not installed -> grab the static
  binary to ~/.local/bin (koalaman release tar.xz). yarn is classic 1.22.x via
  corepack (safe, no yarn.lock migration); deps install clean with --frozen-lockfile.
- FINAL integrated gates after the cycle: shellcheck (error) clean; yarn ci 439
  tests pass (was 395) + main.js idempotent rebuild (two builds byte-identical);
  smoke `all` = 84 passed / 0 failed (was 81; +3 nft v6 regression assertions);
  whole-chain `unshare -rn` confirms v6 tproxy normalizes to [::1]:1603. All 3
  layers code-reviewer APPROVED. Ready for human commit (agents never auto-commit).
