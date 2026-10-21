#!/bin/bash

# save the script directory
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

# pick the musl loader matching the architecture this build was made for
ARCH=${ARCH:-$(uname -m)}
MUSL_LOADER=$SCRIPTPATH/alpine/opt/cfx-server/ld-musl-$ARCH.so.1

if [ ! -f "$MUSL_LOADER" ]; then
    echo "Could not find the musl loader for '$ARCH' at $MUSL_LOADER; this server build may be for a different architecture." >&2
    exit 1
fi

# run server
exec $MUSL_LOADER \
    --library-path "$SCRIPTPATH/alpine/usr/lib/v8/:$SCRIPTPATH/alpine/lib/:$SCRIPTPATH/alpine/usr/lib/" -- \
    $SCRIPTPATH/alpine/opt/cfx-server/FXServer +set citizen_dir $SCRIPTPATH/alpine/opt/cfx-server/citizen/ $*
