# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Podkop Evolution is a domain routing application for OpenWrt routers that provides proxy functionality using sing-box. This fork adds subscription URL support with custom headers (HWID, Device-OS, Device-Model) and automatic updates. The project consists of:

- **Backend**: Shell scripts (ash/dash) that manage sing-box configuration, nftables rules, DNS routing, and subscription handling
- **Frontend**: TypeScript-based LuCI web interface for configuration
- **Packages**: OpenWrt packages (ipk/apk) for installation on routers

## Architecture

### Core Components

1. **Main Binary** (`podkop/files/usr/bin/podkop`): Main entry point that orchestrates all operations. Sources library modules and handles commands like `start`, `stop`, `subscription_update`, `show_version`.

2. **Library Modules** (`podkop/files/usr/lib/*.sh`):
   - `constants.sh`: Global constants (versions, paths, network settings, sing-box configuration tags)
   - `helpers.sh`: Validation functions (IPv4, domains, base64, version comparison)
   - `logging.sh`: Logging utilities
   - `nft.sh`: nftables management for traffic routing
   - `rulesets.sh`: Domain/IP ruleset management
   - `sing_box_config_manager.sh`: Low-level sing-box JSON configuration builder (functions prefixed `sing_box_cm_*`)
   - `sing_box_config_facade.sh`: High-level sing-box configuration interface (functions prefixed `sing_box_cf_*`)

3. **Configuration**: UCI-based config at `/etc/config/podkop` with sections for proxy settings, DNS, routing rules, and subscription URLs.

4. **Frontend** (`fe-app-podkop/`): TypeScript application that compiles to JavaScript for LuCI interface. Uses tsup for bundling.

### Key Features

- **Subscription Support**: Fetches proxy server lists from subscription URLs with custom headers (HWID, device info)
- **Automatic Updates**: Configurable intervals (30min-1day) for subscription refresh
- **Traffic Routing**: Uses nftables + sing-box for selective domain/IP routing through proxy
- **DNS Management**: Integrates with dnsmasq, supports FakeIP for efficient routing
- **Multiple Proxy Types**: VLESS, Shadowsocks, Selector, URLTest (auto-select by latency)

## Development Commands

### Backend (Shell Scripts)

**Linting**:
```bash
# ShellCheck runs automatically in CI on push/PR
# To run locally, check specific files:
shellcheck podkop/files/usr/bin/podkop
shellcheck podkop/files/usr/lib/*.sh
shellcheck install.sh
```

**Testing**:
- Unit tests planned using BATS framework (not yet implemented)
- Integration tests planned for OpenWrt rootfs (not yet implemented)

### Frontend

**Setup**:
```bash
cd fe-app-podkop
yarn install
```

**Development**:
```bash
yarn dev          # Watch mode compilation
yarn build        # Production build
yarn format       # Format code with Prettier
yarn lint         # Run ESLint
yarn lint:fix     # Fix linting issues
yarn test         # Run tests (vitest)
yarn ci           # Full CI pipeline: format + lint + test + build
```

**Localization**:
```bash
yarn locales:actualize  # Extract, generate POT/PO, distribute translations
```

### Building Packages

Packages are built via GitHub Actions workflows. The build system uses OpenWrt SDK:

- `.github/workflows/build.yml`: Main package builds (ipk/apk)
- `.github/workflows/frontend-ci.yml`: Frontend quality checks
- `.github/workflows/shellcheck.yml`: Shell script linting

## Configuration Structure

The UCI config (`/etc/config/podkop`) uses sections with:
- `connection_type`: `proxy` or `direct`
- `proxy_config_type`: `url`, `selector`, `urltest`, `subscription`, `json`, or `interface`
- For subscriptions: `subscription_url` and `subscription_update_interval`
- `community_lists`: Pre-defined domain lists (russia_inside, russia_outside, etc.)

## Important Constraints

- **OpenWrt Version**: Requires OpenWrt 24.10+ (23.05 not supported since v0.5.0)
- **Dependencies**: sing-box ≥1.12.0, jq ≥1.7.1, coreutils-base64 ≥9.7
- **Storage**: Minimum 25MB free space required
- **Conflicts**: Cannot coexist with https-dns-proxy, nextdns, passwall packages
- **Shell**: Scripts use ash/dash (POSIX-compliant, no bashisms)

## Code Conventions

- Shell functions in `sing_box_config_manager.sh` prefixed with `sing_box_cm_*`
- Shell functions in `sing_box_config_facade.sh` prefixed with `sing_box_cf_*`
- All shell scripts must pass ShellCheck with severity=error
- Frontend uses TypeScript with strict type checking
- Version substitution: `__COMPILED_VERSION_VARIABLE__` replaced during package build

## Testing Approach

When modifying shell scripts:
1. Ensure POSIX compliance (no bashisms)
2. Test with shellcheck
3. Verify UCI config parsing logic
4. Check sing-box JSON generation validity

When modifying frontend:
1. Run `yarn ci` before committing
2. Test in actual LuCI environment if possible
3. Clear browser cache when testing updates
