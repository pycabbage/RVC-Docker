#!/bin/bash -e

PYTHON_PATH=${1:-"/opt/runtime/bin/python3"}
RUNTIME_PATH=${2:-"/opt/runtime"}
REQUIREMENTS_PATH=${3:-"/tmp/requirements.txt"}

echo "Creating runtime at ${RUNTIME_PATH}"

"$PYTHON_PATH" -m venv --copies /opt/runtime
(
  . /opt/runtime/bin/activate
  # upgrade pip
  python3 -m pip install --upgrade --no-cache-dir pip
  # install pytorch
  pip install --no-cache-dir torch torchvision torchaudio
  # install prebuilt wheels
  pip install --no-cache-dir https://github.com/pycabbage/RVC-Docker/releases/download/wheel/fairseq-0.12.2-cp310-cp310-linux_x86_64.whl
  pip install --no-cache-dir https://github.com/pycabbage/RVC-Docker/releases/download/wheel/pyworld-0.3.2-cp310-cp310-linux_x86_64.whl
  # install requirements
  pip install --no-cache-dir -r /tmp/requirements.txt
)
