# syntax=docker/dockerfile:1

FROM ubuntu:20.04 as base
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update

FROM base as cloner
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get install git ca-certificates \
  -y --no-install-recommends
ARG RVC_TAG="updated1006v2"
RUN git clone https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI.git --branch ${RVC_TAG} --depth 1 /opt/rvc

FROM base as python_builder
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get install build-essential libssl-dev zlib1g-dev \
  libbz2-dev libreadline-dev libsqlite3-dev curl \
  libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
  -y --no-install-recommends

# ARG PYTHON_VERSION=3.11.7
ARG PYTHON_VERSION=3.10.13
# ARG PYTHON_VERSION=3.9.18
# ARG PYTHON_VERSION=3.8.18

# Download python source
RUN curl "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz" -kLo /tmp/Python.tgz && \
  tar axf /tmp/Python.tgz -C /tmp && \
  rm /tmp/Python.tgz

# Build python
RUN mkdir /tmp/build-python
WORKDIR /tmp/build-python
RUN /tmp/Python-${PYTHON_VERSION}/configure \
  --prefix=/tmp/python \
  --enable-loadable-sqlite-extensions \
  --enable-optimizations \
  --enable-ipv6 \
  && \
  make -j$(nproc) && \
  make install
WORKDIR /tmp/python
RUN rm -rf /tmp/build-python

FROM nvidia/cuda:11.6.2-cudnn8-runtime-ubuntu20.04 as cuda
ARG USERNAME=rvc
ARG GROUPNAME=rvc
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID $GROUPNAME && \
  useradd -m -s /bin/bash -u $UID -g $GID $USERNAME
USER $USERNAME

# Create runtime environment directory
USER root
RUN mkdir /opt/runtime && \
  chown ${USERNAME}:${GROUPNAME} /opt/runtime
USER $USERNAME

FROM base as model_download
COPY --from=cloner --chown=${USERNAME}:${GROUPNAME} /opt/rvc /opt/rvc
WORKDIR /opt/rvc

ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get install aria2 ca-certificates \
  -y --no-install-recommends

RUN --mount=type=bind,source=models_url.txt,target=/opt/rvc/models_url.txt,ro \
  aria2c --console-log-level=error -c -x 16 -s 16 -k 1M -i models_url.txt

FROM cuda as create_runtime
# Install curl
USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  apt-get install -y curl ca-certificates -y
USER $USERNAME

COPY --from=python_builder --chown=${USERNAME}:${GROUPNAME} /tmp/python /opt/python
RUN /opt/python/bin/python3 -m venv --copies /opt/runtime
RUN . /opt/runtime/bin/activate && python3 -m pip install --upgrade pip
# install pytorch
RUN \
  . /opt/runtime/bin/activate && \
  pip install --no-cache-dir torch torchvision torchaudio
# install prebuilt wheels
RUN \
  . /opt/runtime/bin/activate && \
  pip install https://github.com/pycabbage/RVC-Docker/releases/download/wheel/fairseq-0.12.2-cp310-cp310-linux_x86_64.whl && \
  pip install https://github.com/pycabbage/RVC-Docker/releases/download/wheel/pyworld-0.3.2-cp310-cp310-linux_x86_64.whl
# install requirements
#RUN \
  --mount=type=bind,from=cloner,source=/opt/rvc/requirements.txt,target=/tmp/requirements.txt,ro \
  . /opt/runtime/bin/activate && \
  pip install --no-cache-dir -r /tmp/requirements.txt

FROM cuda as final
COPY --from=model_download --chown=${USERNAME}:${GROUPNAME} /opt/rvc /opt/rvc
COPY --from=python_builder --chown=${USERNAME}:${GROUPNAME} /tmp/python /opt/python
COPY --from=create_runtime --chown=${USERNAME}:${GROUPNAME} /opt/runtime /opt/runtime
WORKDIR /opt/rvc

# Install ffmpeg
USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update && \
  apt-get install -y ffmpeg -y --no-install-recommends
USER $USERNAME

EXPOSE 7897
ENV NVIDIA_DRIVER_CAPABILITIES=compute,graphics,utility
CMD [ "/opt/runtime/bin/python3", "infer-web.py" ]
