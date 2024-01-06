#!/bin/bash -e

ARCHIVE_PATH="${1:-"/tmp/$(ls /tmp | grep "ffmpeg-*" --color=none)"}"
test -f "${ARCHIVE_PATH}" || (echo "File not found: ${ARCHIVE_PATH}" && exit 1)
echo "Installing ffmpeg from ${ARCHIVE_PATH}"
ls -l /tmp
tar axf "${ARCHIVE_PATH}" -C $HOME/.local
