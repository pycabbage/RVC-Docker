#!/bin/bash -e

ARCHIVE_PATH="${1}"
ARCHIVE_EXTRACT_DIR="${ARCHIVE_PATH%\.tar\.*}"

echo "Installing ffmpeg from ${ARCHIVE_PATH}"

ls -l /tmp
tar axf "${ARCHIVE_PATH}" -C $HOME/.local
# mv -r "${ARCHIVE_EXTRACT_DIR}/*" $HOME/.local
