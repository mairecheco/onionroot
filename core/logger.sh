#!/usr/bin/env bash
# OnionRoot — core/logger.sh
# Structured logging to file

function _write_log() {
    local level="$1"; shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] [${level}] ${message}" >> "$OR_LOG_FILE" 2>/dev/null || true
}

function log_info()  { _write_log "INFO"  "$@"; }
function log_warn()  { _write_log "WARN"  "$@"; }
function log_error() { _write_log "ERROR" "$@"; }
function log_debug() { [[ "${OR_DEBUG:-0}" == "1" ]] && _write_log "DEBUG" "$@" || true; }

function log_err() {
    or_err "$@"
    log_error "$@"
}
