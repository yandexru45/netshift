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
- Corrupted mojibake bytes in diagnostic strings (should be byte-preserved).
