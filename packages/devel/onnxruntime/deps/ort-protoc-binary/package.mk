# SPDX-License-Identifier: GPL-2.0-or-later
# Source-only dependency pinned by ONNX Runtime v1.23.2 cmake/deps.txt.
PKG_NAME="ort-protoc-binary"
PKG_VERSION="protoc-21.12-linux-x86_64"
PKG_SHA256="3a4c1e5f2516c639d3079b1586e703fc7bcfa2136d58bda24d1d54f949c315e8"
PKG_LICENSE="BSD-3-Clause"
PKG_URL="https://github.com/protocolbuffers/protobuf/releases/download/v21.12/protoc-21.12-linux-x86_64.zip"
PKG_SOURCE_NAME="ort-protoc-binary-protoc-21.12-linux-x86_64.zip"
PKG_SOURCE_DIR="ort-protoc-binary-protoc-21.12-linux-x86_64"
PKG_TOOLCHAIN="manual"
PKG_LONGDESC="Pinned source archive used privately by ONNX Runtime."

unpack() {
  mkdir -p "${PKG_UNPACK_DIR}/${PKG_SOURCE_DIR}"
  unzip -q "${SOURCES}/${PKG_NAME}/${PKG_SOURCE_NAME}" -d "${PKG_UNPACK_DIR}/${PKG_SOURCE_DIR}"
}
