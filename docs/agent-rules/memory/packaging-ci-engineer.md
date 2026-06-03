# Memory — packaging-ci-engineer

Durable packaging / CI / release knowledge. Read before working; append
findings; keep under ~200 lines.

## Packages

- `netshift` (backend) and `luci-app-netshift` (UI; also yields
  `luci-i18n-netshift-ru` via `LUCI_LANGUAGES=en ru`). Both `PKGARCH=all`.
- `netshift/Makefile`: DEPENDS `+sing-box +curl +jq +kmod-nft-tproxy
  +coreutils-base64 +bind-dig`; CONFLICTS `https-dns-proxy nextdns
  luci-app-passwall luci-app-passwall2`; version
  `PKG_VERSION = $(if $(NETSHIFT_VERSION),$(NETSHIFT_VERSION),0.$(date +%d%m%Y))`;
  `prerm` removes `105 netshift` from `/etc/iproute2/rt_tables` and stops the
  service; conffile `/etc/config/netshift`; stamps
  `__COMPILED_VERSION_VARIABLE__` into `constants.sh` via sed (NO `|| true`, so a
  missing file fails the build).
- `luci-app-netshift/Makefile`: uses `luci.mk`, `LUCI_DEPENDS=+luci-base
  +netshift`; stamps the same placeholder into `main.js` (WITH `|| true`, so a
  missing main.js silently won't stamp). Asymmetric on purpose — note it.

## Docker build images

- `Dockerfile-ipk` FROM `itdoginfo/openwrt-sdk-ipk:24.10.6`;
  `Dockerfile-apk` FROM `itdoginfo/openwrt-sdk-apk:25.12.3`.
- KNOWN INCONSISTENCY (intentional, do NOT "fix" blindly): ipk Dockerfile
  exports `NETSHIFT_VERSION="v${NETSHIFT_VERSION}"` (adds a `v`); apk sets it
  raw (no `v`). Embedded version vs artifact filenames can differ across types.
- `sdk/Dockerfile-sdk-*` are the base SDK images (feeds update + luci-base);
  apk SDK requires running `./setup.sh` first.

## Release flow (build.yml, on tag push)

smoke-tests gate -> `preparation` derives version (`git describe --tags
--exact-match`, fallback `0.<date>`) -> matrix build ipk+apk -> `docker cp`
artifacts out of the container -> **ipk underscore->dash rename**
(`sed 's/_/-/g'`) -> filter to the 3 packages -> GitHub Release.

- The underscore->dash rename is LOAD-BEARING: `install.sh` scrapes the
  latest-release API and matches assets by package-name prefix
  (`netshift*`, `luci-app-netshift*`, `luci-i18n-netshift-ru*`). Breaking the
  rename breaks install.

## Smoke tests (tests/)

- Image = OpenWRT 24.10.6 rootfs; source is **bind-mounted at runtime**
  (`../netshift/files -> /netshift/files:ro`), so editing `netshift/files` is
  picked up without rebuilding the image.
- Needs `NET_ADMIN`/`NET_RAW`/`SYS_ADMIN` + `network_mode: host` for nft/dns;
  nft tests FAIL (not skip) without caps.
- `all` runs: deps syntax config helpers jq cm sb nft diagnostics subscription.
- Add a test: `test_xyz()` (header/pass/fail/skip), add to `main()` `all)` list,
  add `case` alias, update usage line + docker-compose comment. Keep the two
  compose invocations (build.yml smoke vs openwrt-smoke-tests.yml) in sync.

## CI gates by path

- `frontend-ci.yml`: PRs touching `fe-app-netshift/**` -> yarn install /
  format(diff) / lint(--max-warnings=0) / test / build(diff).
- `shellcheck.yml`: `install.sh` + `usr/bin/netshift` + `usr/lib/**.sh`,
  severity error (Differential ShellCheck).
- `openwrt-smoke-tests.yml`: `netshift/**`, `luci-app-netshift/**`, `tests/**`,
  `install.sh`, Dockerfiles -> entrypoint `all`.
- `.gitlab-ci.yml` declares a `test` stage but runs no tests — only builds and
  deploys Docker on master. Quality is enforced by the AI review workflow + the
  GitHub Actions above, not GitLab.

## install.sh

- POSIX; apk/opkg abstraction; podkop->netshift migration STOPS the old service
  first (that restores dnsmasq keys + removes PodkopTable + `105 podkop`),
  backs up config to `/etc/config/podkop.bak.pre-netshift`. OpenWRT 23.05
  unsupported; needs >=15 MB on `/overlay`; NO uninstall path (removal lives in
  package `prerm`). GitHub API rate-limit is a known fragility (wget path has no
  guard).
