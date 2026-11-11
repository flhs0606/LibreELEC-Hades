# SPDX-License-Identifier: GPL-2.0-or-later
PKG_NAME="pgs-ocr-model"
PKG_VERSION="5.0-1"
PKG_LICENSE="Apache-2.0"
PKG_SITE="https://github.com/PaddlePaddle/PaddleOCR"
PKG_DEPENDS_TARGET="toolchain"
PKG_TOOLCHAIN="manual"
PKG_LONGDESC="Pinned PP-OCRv5 mobile recognition model; no runtime network or Python."

makeinstall_target() {
  echo "2157a3afca502e6fc23e4679de4e46c9e855247bcda645c8faa02c9e5bd011c1  ${PKG_DIR}/files/ppocrv5-mobile-rec-int8.onnx" | sha256sum -c - || exit 1
  mkdir -p "${INSTALL}/usr/share/kodi/system/ocr"
  cp "${PKG_DIR}/files/ppocrv5-mobile-rec-int8.onnx" \
    "${PKG_DIR}/files/LICENSE" "${PKG_DIR}/files/MODEL.md" \
    "${INSTALL}/usr/share/kodi/system/ocr/"
}
