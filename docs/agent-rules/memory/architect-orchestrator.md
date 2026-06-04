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
