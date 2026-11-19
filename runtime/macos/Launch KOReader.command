#!/bin/sh
set -eu
READER_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export KO_HOME="$READER_ROOT/test-data"
export EMULATE_READER_W=600
export EMULATE_READER_H=800
export EMULATE_READER_DPI=167
exec "$READER_ROOT/KOReader.app/Contents/MacOS/koreader" "$READER_ROOT/books/The Other Side of the Bridge.epub"
