#!/bin/bash -e

ARCHIVE_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2024-01-05-12-55/ffmpeg-n6.1.1-linux64-gpl-shared-6.1.tar.xz"
ARCHIVE_NAME=$(basename "$ARCHIVE_URL")
FOLDER_NAME=$(basename "${ARCHIVE_URL%\.tar\.*}")

echo "Installing ffmpeg from ${ARCHIVE_URL}"

curl -kLo "/tmp/${ARCHIVE_NAME}" "$ARCHIVE_URL"
tar axf "/tmp/${ARCHIVE_NAME}" -C /tmp
mv -r "/tmp/${FOLDER_NAME}/*" $HOME/.local
rm "/tmp/${ARCHIVE_NAME}"
