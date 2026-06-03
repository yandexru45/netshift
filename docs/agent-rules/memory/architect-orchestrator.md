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

## Workflow facts

- Contribution gating: `CODEOWNERS=@yandexru45`; PRs accepted only after Telegram
  coordination with authors (README). Reflect this in `/describe` output.
