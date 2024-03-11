# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.9.18
ARG RUNTIME_USERNAME="rvc"

FROM ubuntu:20.04 as base
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  apt-get install -y \
  build-essential libssl-dev zlib1g-dev \
  libbz2-dev libreadline-dev libsqlite3-dev curl \
  libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
  sudo git aria2
ARG RUNTIME_USERNAME
RUN --mount=type=bind,source=scripts/add-nonroot-user.sh,target=/tmp/add-nonroot-user.sh \
  bash /tmp/add-nonroot-user.sh "${RUNTIME_USERNAME}"

# Download ffmpeg and pretrained models and repo
FROM base as downloader
ARG RVC_TAG="updated1006v2"
ARG RVC_REPO="https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI"
WORKDIR /tmp
RUN curl -kLo "ffmpeg.tar.xz" \
  "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n6.1-latest-linux64-lgpl-shared-6.1.tar.xz" && \
  tar axf "ffmpeg.tar.xz" && \
  mv ffmpeg-* /opt/ffmpeg && \
  chown -R ${RUNTIME_USERNAME}:${RUNTIME_USERNAME} /opt/ffmpeg && \
  rm "ffmpeg.tar.xz"
# Download repo
USER root
WORKDIR /
RUN git clone --depth 1 -b "${RVC_TAG}" "${RVC_REPO}" /app && \
  chown -R ${RUNTIME_USERNAME}:${RUNTIME_USERNAME} /app
# Download pretrained models
WORKDIR /app
RUN mkdir assets/pretrained_v2 assets/uvr5_weights assets/hubert assets/rmvpe -p
RUN --mount=type=bind,source=pretrained_models.txt,target=/tmp/pretrained_models.txt \
  aria2c --console-log-level=error -c -x 16 -s 16 -k 1M -i /tmp/pretrained_models.txt

# Build python
FROM base as python_builder
ARG PYTHON_VERSION

USER ${RUNTIME_USERNAME}
WORKDIR /tmp
RUN curl -kLO "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz" && \
  tar axf "Python-${PYTHON_VERSION}.tar.xz" && \
  rm "Python-${PYTHON_VERSION}.tar.xz"

WORKDIR /tmp/Python-${PYTHON_VERSION}
USER root
RUN ./configure \
  --with-lto \
  --with-ensurepip \
  --enable-optimizations \
  --enable-loadable-sqlite-extensions \
  --enable-ipv6 \
  --enable-shared \
  --prefix="/opt/python${PYTHON_VERSION}" && \
  make -j$(nproc) && \
  make install && \
  chown -R ${RUNTIME_USERNAME}:${RUNTIME_USERNAME} "/opt/python${PYTHON_VERSION}" && \
  cd .. && rm -fr "Python-${PYTHON_VERSION}"
WORKDIR /tmp

# FROM ubuntu:20.04 as cuda_base
FROM nvidia/cuda:11.6.2-cudnn8-runtime-ubuntu20.04 as cuda_base

ARG RUNTIME_USERNAME
ARG PYTHON_VERSION

USER root
# add nonroot user
RUN --mount=type=bind,source=scripts/add-nonroot-user.sh,target=/tmp/add-nonroot-user.sh \
  bash /tmp/add-nonroot-user.sh "${RUNTIME_USERNAME}"
# Copy python
COPY --from=python_builder --chown=${RUNTIME_USERNAME}:${RUNTIME_USERNAME} \
  /opt/python${PYTHON_VERSION} /opt/python${PYTHON_VERSION}
RUN echo "/opt/python${PYTHON_VERSION}/lib" > /etc/ld.so.conf.d/libpython.conf && \
  ldconfig
# Copy repo
COPY --from=downloader --chown=${RUNTIME_USERNAME}:${RUNTIME_USERNAME} \
  /app /app
WORKDIR /app
ENV PATH="/opt/python${PYTHON_VERSION}/bin:/opt/ffmpeg/bin:${PATH}"

FROM cuda_base as venv_builder

ARG RUNTIME_USERNAME
ARG PYTHON_VERSION

RUN --mount=type=cache,target=${HOME}/.cache/pip,sharing=locked \
  python3 -m pip install -U pip virtualenv && \
  python3 -m virtualenv --download --setuptools bundle --wheel bundle --activators bash venv
RUN --mount=type=cache,target=${HOME}/.cache/pip,sharing=locked \
  . ./venv/bin/activate && \
  ./venv/bin/python3 -m pip install -U pip && \
  PYTHON_VERSION_CODE=$(python3 -c 'from sys import version_info;print("cp{}{}".format(version_info.major,version_info.minor))') && \
  ./venv/bin/pip install https://github.com/pycabbage/RVC-Docker/releases/download/wheel/fairseq-0.12.2-${PYTHON_VERSION_CODE}-${PYTHON_VERSION_CODE}-linux_x86_64.whl && \
  ./venv/bin/pip install https://github.com/pycabbage/RVC-Docker/releases/download/wheel/pyworld-0.3.2-${PYTHON_VERSION_CODE}-${PYTHON_VERSION_CODE}-linux_x86_64.whl
RUN --mount=type=cache,target=${HOME}/.cache/pip,sharing=locked \
  . ./venv/bin/activate && \
  ./venv/bin/pip install --no-cache-dir --no-color --no-input -U -r requirements.txt && \
  du -sh ./venv

FROM venv_builder as final

ARG RUNTIME_USERNAME
ARG PYTHON_VERSION

COPY --from=downloader --chown=${RUNTIME_USERNAME}:${RUNTIME_USERNAME} \
  /opt/ffmpeg /opt/ffmpeg
# COPY --from=downloader --chown=${RUNTIME_USERNAME}:${RUNTIME_USERNAME} \
#   /app /app
# COPY --from=venv_builder --chown=${RUNTIME_USERNAME}:${RUNTIME_USERNAME} \
#   /app/venv /app/venv

USER ${RUNTIME_USERNAME}
EXPOSE 7865
WORKDIR /app

VOLUME [ \
  "/app/assets", \
  "/app/opt", \
  "/app/logs", \
]
CMD ["/app/venv/bin/python3", "infer-web.py"]
