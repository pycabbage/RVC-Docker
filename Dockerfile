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

ARG PYTHON_VERSION=3.11.7

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

FROM nvidia/cuda:11.6.2-cudnn8-runtime-ubuntu20.04 as final
ARG USERNAME=rvc
ARG GROUPNAME=rvc
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID $GROUPNAME && \
  useradd -m -s /bin/bash -u $UID -g $GID $USERNAME
USER $USERNAME

COPY --from=python_builder --chown=${USERNAME}:${GROUPNAME} /tmp/python /opt/python
COPY --from=cloner --chown=${USERNAME}:${GROUPNAME} /opt/rvc /opt/rvc
WORKDIR /opt/rvc
RUN /opt/python/bin/python3 -m pip install --user --upgrade pip
RUN /opt/python/bin/python3 -m pip install --user -r requirements.txt

EXPOSE 7897
CMD ["/opt/python/bin/python3"]
