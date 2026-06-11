# Memory — code-reviewer

Reusable review findings and check focus for NetShift. Read before reviewing;
append recurring findings; keep under ~200 lines.

## What to check (in priority order)

1. **Architecture / layer direction**: UI -> backend (via fs.exec of the two
   allowed binaries) -> sing-box/nft/dnsmasq. No layer skips another. UI must
   not reimplement backend logic; backend must not hardcode what belongs in
   `constants.sh`.
2. **Runtime contract intact**: ports/marks/paths (1602, 127.0.0.42:53, :9090,
   198.18.0.0/15, marks 0x100000/0x200000, `NetShiftTable`, `105 netshift`)
   unchanged unless the task explicitly says so and the WHOLE chain is updated.
3. **Backend shell correctness**: `# shellcheck shell=ash`; all `local`; correct
   function prefix; `$config` echo-and-reassign threading; **no jq regex**
   (test/match/sub/gsub) — flag any as CRITICAL; `fatal` log followed by
   `exit 1`; atomic write + `sing-box check`; new constants in `constants.sh`.
4. **Frontend correctness**: did they edit TS source (not `main.js` by hand)?
   Did they rebuild so `main.js` matches (no stray diff)? New public API
   re-exported up the barrel to `main.*`? Unused vars `_`-prefixed? `_()` around
   new user-facing literals? No `any`?
5. **Test coverage / gates**: backend config-gen or subscription changes should
   add/extend a smoke test; new pure frontend logic should ship a vitest
   `.test.js`. Confirm the relevant gate (shellcheck / smoke-tests / yarn ci)
   was run.
6. **Packaging**: respect the intentional ipk `v`-prefix vs apk-raw
   inconsistency; don't break the underscore->dash rename; version placeholder
   stamping intact.

## Output

- Write the review to `docs/tasks/<task-name>-review-001.md` using
  `docs/tasks/TEMPLATE-review.md`.
- Verdict vocabulary: `APPROVED` / `APPROVED WITH CONDITIONS` /
  `REQUIRES CHANGES`. ID-tag issues (C1 critical, S1 significant, M1 minor) and
  cite exact `file:line`.
- No flattery. No speculation — report only what you can verify. Every problem
  gets a concrete recommendation.

## Recurring findings to watch for

- jq regex functions sneaking in (CRITICAL on OpenWRT jq).
- `fatal` log without a following `exit 1`.
- Hand-edited `main.js` or a `main.js` that doesn't match a fresh build.
- New validator/helper not re-exported -> invisible to `main.*`.
- Hardcoded ports/IPs/paths instead of `constants.sh` references.
- Routing code that ignores `subscription_outbound_is_unavailable` (traffic
  leak when a subscription is down).
- Scope creep: unrelated file churn (e.g. lockfile churn) flagged as Minor.
- Diagnostic strings in `usr/bin/netshift` are valid UTF-8 emoji/box-drawing —
  must stay UTF-8, never CP1251 (task-004 fixed a double-encode). For
  mojibake-repair reviews, prove ASCII-byte preservation byte-safely (Python:
  decode HEAD blob vs working tree, strip `[^\x00-\x7F]` per line, expect 0
  mismatched lines); beware PowerShell text pipelines which produce false UTF-16
  diffs.

- base64 share-link decode vs `sing_box_cf_add_proxy_outbound` `url_decode` (facade:65): the facade runs `url_decode` (+>space, %XX>byte) on the whole URL before the scheme case. Any case that base64-decodes the ENTIRE payload (vmess, future tuic/etc.) must use the RAW pre-url_decode link � standard base64 contains '+'. The ss) case escapes this only because it decodes a short method:password userinfo. Beware synthetic test keys that avoid '+' masking this (false green).

- For protocol validators that base64-decode a whole body (vmess, future tuic/etc.): the '+'-regression is real only if the dispatcher preserves '+'. validateProxyUrl only .trim()s, so '+' survives at the boundary � a green direct-call '+' test is sufficient evidence; a dispatcher-level '+' assertion is the stronger guard.

- Wrapper/core split for always-run cleanup (task-009 core-switch): verify the public wrapper captures core stdout to a temp file + rc, then UNCONDITIONALLY calls restore/cleanup before re-emitting JSON and return rc; confirm the worker runs without set -e (else a non-zero core rc could skip trailing cleanup) and that _*_core never exits. For never-end-core-less rollbacks, confirm the tmpfs backup happens BEFORE the package manager/extract touches the binary and is dropped ONLY on the confirmed-good path; strongest test deletes the live mock binary on simulated failure and asserts original bytes restored.

- Frontend barrel exposure: anything added to src/helpers/index.ts (or any export* barrel reaching main.ts) AND actually used appears in the generated main.js baseclass.extend block as a main.* symbol; unused re-exports get tree-shaken. So internal-only helper + added to barrel + used = it WILL leak to main.*. To keep a helper truly internal, place it in the consuming module, not the barrel.

- OpenWrt jq ascii_downcase only folds ASCII A-Z; case-insensitive matching on Cyrillic/Unicode names needs an inline codepoint fold (explode/map/implode: ASCII 65-90 +32, Cyrillic 1040-1071 +32, Yo 1025->1105). When reviewing such a fold: (a) already-lowercase ranges excluded (no double-fold), (b) def before first use when the program does NOT import helpers.jq, (c) a pure-emoji-keyword exact-match test proves non-folded codepoints pass through unchanged on both sides. (task-010)

- Package-manager rc is NOT a reliable success signal on opkg: rc=0 for "Not downgrading"/"already installed"/"up to date". A self-update/install that trusts only rc silently no-ops (the v→no-v rename trap: legacy `v0.8.6` sorts ABOVE `0.8.7` in opkg's compare, so `opkg install` refuses the "downgrade" and returns 0). When reviewing a package-install path, require: (a) `--force-downgrade --force-reinstall` on the opkg branch (apk overwrites by default); AND (b) verify-after-install — RE-READ the installed version (opkg `list-installed | grep "^pkg "`, apk `list --installed`; grep/awk only, NO Oniguruma jq) and compare v-stripped semver (`${x#v}`, `${x%%-*}`) with `==` OR `is_min_package_version installed target`; empty-installed must fail-safe to success:false. Keep install.sh `pkg_install` and updater.sh `updates_pkg_install_file` opkg branches ALIGNED. (task-041/042)
- Async self-update worker landmine: the `_*_core` worker MUST `return 1` (NEVER `exit`) on failure so the public wrapper's always-run `updates_restore_after_swap` epilogue + finished-job-state write still execute. Verify the wrapper captures core rc/JSON to a temp file then unconditionally restores. Smoke assertions for these must be in the MAIN shell body (direct `if…pass/fail`), never inside `cmd | while read` (subshell swallows PASS/FAIL — harness-wide landmine). (task-041)
