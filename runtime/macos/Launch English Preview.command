#!/bin/sh
set -eu
READER_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export KINDLE_ENGLISH_PREVIEW="${KINDLE_ENGLISH_PREVIEW:-read}"
exec "$READER_ROOT/Launch KOReader.command"
