# Contributing to OnionRoot

Thank you for contributing to OnionRoot. This guide explains how to add modules, report bugs, and submit pull requests.

## Architecture

OnionRoot is split into:

- `onionroot` — main CLI entry point, parses commands and routes to modules
- `core/` — shared config, logging, and utilities sourced by every module
- `modules/` — each feature is a self-contained bash script (or Python script)
- `data/` — seed files and static data

Every module is sourced by the main script, not executed as a subprocess. This lets modules share the core functions directly.

## Adding a New Module

**1. Create `modules/yourmodule.sh`**

```bash
#!/usr/bin/env bash
# OnionRoot — modules/yourmodule.sh
# Short description of what this does

function mod_yourmodule() {
    local target="${1:-}"

    or_section "Your Module — ${target}"

    # Validate
    [[ -z "$target" ]] && { log_err "Usage: onionroot yourmodule <target>"; exit 1; }

    # Use tor_curl for all HTTP requests
    local body
    body=$(fetch_onion "http://${target}" 2>/dev/null || true)

    # Output using helpers
    or_info "Processing..."
    or_hit "Found something: $target"
    or_kv  "Key"  "Value"

    # Log
    log_info "yourmodule: $target"
}
```

**2. Register it in `onionroot` main script**

Add to the `case` block:

```bash
yourmodule)
    [[ -z "${1:-}" ]] && { log_err "Usage: onionroot yourmodule <target>"; exit 1; }
    check_tor
    source "$ONIONROOT_HOME/modules/yourmodule.sh"
    mod_yourmodule "$1"
    ;;
```

**3. Document it**

Add an entry to the `usage()` function and update README.md.

## Code Style

- Use `or_hit`, `or_info`, `or_warn`, `or_err` for output — never raw `echo` for user-facing messages
- Use `tor_curl` for all HTTP requests — never plain `curl`
- Use `polite_sleep` between requests — be respectful
- Use `log_info`, `log_warn`, `log_error` for file logging
- Validate all inputs before using them
- Handle empty/failed responses gracefully

## Adding Seeds

Add onion addresses to `data/seeds.txt` — one per line, comments with `#`.
Only include publicly known, legitimate services (search engines, indexes, etc.).

## Submitting a PR

1. Fork the repo
2. Create a branch: `git checkout -b feature/your-module`
3. Write and test your changes
4. Validate syntax: `bash -n onionroot && bash -n modules/yourmodule.sh`
5. Submit a pull request with a clear description

## Reporting Issues

Include:
- OS and distro
- Tor version: `tor --version`
- OnionRoot version: `onionroot version`
- Steps to reproduce
- Any error output

## Contact

- Instagram: [@maireche.exe](https://instagram.com/maireche.exe)
- TikTok: [@abdou_mhf7](https://tiktok.com/@abdou_mhf7)
