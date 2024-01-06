#!/bin/bash -e

PYTHON_VERSION=${1:-"${PYTHON_VERSION:-"3.10.13"}"}
PREFIX=${2:-"${PREFIX:-"/tmp/python"}"}

PYTHON_ARCHIVE="Python-${PYTHON_VERSION}.tgz"
PYTHON_ARCHIVE_PATH="/tmp/${PYTHON_ARCHIVE}"
PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_ARCHIVE}"

curl "$PYTHON_URL" -kLo "$PYTHON_ARCHIVE_PATH"
tar axf "$PYTHON_ARCHIVE_PATH" -C /tmp
rm "$PYTHON_ARCHIVE_PATH"

(
  mkdir "/tmp/build-python"
  cd "/tmp/build-python"
  "/tmp/Python-${PYTHON_VERSION}/configure" \
    --prefix=/tmp/python \
    --enable-loadable-sqlite-extensions \
    --enable-optimizations \
    --enable-ipv6
  make -j$(nproc)
  make install
  cd ..
  rm -rf "/tmp/build-python"
)
