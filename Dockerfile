# syntax=docker/dockerfile:1

FROM ubuntu:22.04 as base
RUN DEBIAN_FRONTEND=noninteractive && \
  apt-get update -qq && \
  apt-get install -y --no-install-recommends -qq \
  git curl aria2 ca-certificates

FROM base as cloner
ARG RVC_TAG="updated1006v2"
RUN git clone https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI.git --branch ${RVC_TAG} --depth 1 /opt/rvc

FROM base as python_builder
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  DEBIAN_FRONTEND=noninteractive && \
  apt-get install build-essential libssl-dev zlib1g-dev \
  libbz2-dev libreadline-dev libsqlite3-dev curl \
  libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
  -y --no-install-recommends -qq

# ARG PYTHON_VERSION=3.11.7
ARG PYTHON_VERSION=3.10.13
# ARG PYTHON_VERSION=3.9.18
# ARG PYTHON_VERSION=3.8.18

# Build python
RUN --mount=type=bind,source=scripts/build-python.sh,target=/tmp/build-python.sh,ro \
  . /tmp/build-python.sh \
    "/tmp/python" \
    "${PYTHON_VERSION}"

FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 as cuda
# Add non-root user
ARG RUNTIME_USERNAME=rvc
ARG RUNTIME_GROUPNAME=rvc
ARG RUNTIME_UID=1000
ARG RUNTIME_GID=1000
RUN groupadd -g $RUNTIME_GID $RUNTIME_GROUPNAME && \
  useradd -m -s /bin/bash -u $RUNTIME_UID -g $RUNTIME_GID $RUNTIME_USERNAME

# Create runtime environment directory
RUN mkdir /opt/runtime && \
  chown ${RUNTIME_USERNAME}:${RUNTIME_GROUPNAME} /opt/runtime

USER $RUNTIME_USERNAME

FROM base as download
COPY --from=cloner --chown=${USERNAME}:${GROUPNAME} /opt/rvc /opt/rvc
WORKDIR /opt/rvc

RUN --mount=type=bind,source=models_url.txt,target=/opt/rvc/models_url.txt,ro \
  # Download models
  aria2c --console-log-level=error -c -x 16 -s 16 -k 1M -i models_url.txt && \
  # Download ffmpeg
  aria2c -x16 -s16 -c --dir /tmp -o ffmpeg-n6.1.1-linux64-gpl-shared-6.1.tar.xz \
  "https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2024-01-05-12-55/ffmpeg-n6.1.1-linux64-gpl-shared-6.1.tar.xz"

FROM cuda as create_runtime
# Install curl
USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  DEBIAN_FRONTEND=noninteractive && \
  apt-get update -qq && \
  apt-get install -y curl ca-certificates -y -qq
USER $USERNAME

# Create runtime
RUN --mount=type=bind,from=python_builder,source=/tmp/python,target=/opt/python \
  --mount=type=bind,from=cloner,source=/opt/rvc/requirements.txt,target=/tmp/requirements.txt,ro \
  --mount=type=bind,source=scripts/create-runtme.sh,target=/tmp/create-runtme.sh,ro \
  . /tmp/create-runtme.sh \
    /opt/python/bin/python3 \
    /opt/runtime \
    /tmp/requirements.txt 

FROM cuda as final
COPY --from=download --chown=${USERNAME}:${GROUPNAME} /opt/rvc /opt/rvc
COPY --from=python_builder --chown=${USERNAME}:${GROUPNAME} /tmp/python /opt/python
COPY --from=create_runtime --chown=${USERNAME}:${GROUPNAME} /opt/runtime /opt/runtime
WORKDIR /opt/rvc

# Install ffmpeg
RUN --mount=type=bind,source=scripts/install-ffmpeg.sh,target=/tmp/install-ffmpeg.sh,ro \
  --mount=type=bind,from=download,source=/tmp/ffmpeg-n6.1.1-linux64-gpl-shared-6.1.tar.xz,target=/tmp/ffmpeg-n6.1.1-linux64-gpl-shared-6.1.tar.xz,ro \
  set -xe && \
  tar axf "/tmp/ffmpeg-n6.1.1-linux64-gpl-shared-6.1.tar.xz" -C "$HOME/.local"

EXPOSE 7897
ENV NVIDIA_DRIVER_CAPABILITIES=compute,graphics,utility
CMD [ "/opt/runtime/bin/python3", "infer-web.py" ]
