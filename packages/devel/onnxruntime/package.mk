# SPDX-License-Identifier: GPL-2.0-or-later
PKG_NAME="onnxruntime"
PKG_VERSION="1.23.2"
PKG_SHA256="99bcf964ce4e869d823c99b2294562a9050cbfa8e76ec81c8683cb3c7e19c2b4"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/microsoft/onnxruntime"
PKG_URL="https://github.com/microsoft/onnxruntime/archive/refs/tags/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain flatbuffers"
PKG_DEPENDS_UNPACK="ort-abseil-cpp ort-date ort-eigen3 ort-gsl ort-mp11 ort-nlohmann-json ort-onnx ort-protobuf ort-re2 ort-safeint ort-protoc-binary"
PKG_LONGDESC="CPU-only ONNX Runtime for bounded, passive PGS subtitle identification."
PKG_BUILD_FLAGS="-lto"
PKG_TOOLCHAIN="cmake"
PKG_CMAKE_OPTS_TARGET="-Donnxruntime_BUILD_SHARED_LIB=ON \
 -Donnxruntime_BUILD_UNIT_TESTS=OFF -Donnxruntime_BUILD_BENCHMARKS=OFF \
 -Donnxruntime_ENABLE_PYTHON=OFF -Donnxruntime_DISABLE_ML_OPS=ON \
 -Donnxruntime_DISABLE_CONTRIB_OPS=ON -Donnxruntime_ENABLE_LTO=OFF \
 -Donnxruntime_USE_CUDA=OFF -Donnxruntime_USE_OPENMP=OFF -Donnxruntime_DEV_MODE=OFF \
 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_COMPILE_WARNING_AS_ERROR=OFF"

configure_package() {
  PKG_CMAKE_SCRIPT="${PKG_BUILD}/cmake/CMakeLists.txt"
}

post_unpack() {
  # FetchContent still applies its upstream dependency patches, but every
  # archive comes from CE's normal SHA256-verified download cache, offline.
  while IFS=';' read -r key package filename checksum; do
    echo "${checksum}  ${SOURCES}/${package}/${filename}" | sha256sum -c - || exit 1
    sed -i "s|^${key};[^;]*;|${key};${SOURCES}/${package}/${filename};|" \
      "${PKG_BUILD}/cmake/deps.txt"
  done < "${PKG_DIR}/deps.lock"
}

pre_configure_target() {
  # CMake must find the host interpreter explicitly, not the target Python.
  PKG_CMAKE_OPTS_TARGET+=" -DPython_EXECUTABLE=/usr/bin/python3 -DPython3_EXECUTABLE=/usr/bin/python3"
}

post_makeinstall_target() {
  mkdir -p "${INSTALL}/usr/share/licenses/onnxruntime"
  cp "${PKG_BUILD}/LICENSE" "${PKG_BUILD}/ThirdPartyNotices.txt" \
    "${INSTALL}/usr/share/licenses/onnxruntime/"
}
