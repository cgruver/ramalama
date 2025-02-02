#!/usr/bin/env bash

function cmakeCheckWarnings() {
  awk -v rc=0 '/CMake Warning:/ { rc=1 } 1; END {exit rc}'
}

function cloneAndBuild() {
  local git_repo=${1}
  local git_sha=${2}
  local cmake_flags=${3}
  local install_prefix=${4}
  local work_dir=$(mktemp -d)

  git clone ${git_repo} ${work_dir}
  cd ${work_dir}
  git submodule update --init --recursive
  git reset --hard ${git_sha}
  cmake -B build ${cmake_flags[@]} 2>&1 | cmake_check_warnings
  cmake --build build --config Release -j$(nproc) -v 2>&1 | cmake_check_warnings
  cmake --install build --prefix ${install_prefix} 2>&1 | cmake_check_warnings
  cd -
  rm -rf ${work_dir}
}

function dnfInstallUbi() {

  local packages=${1}
  local url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
  local uname_m=$(uname -m)

  dnf install -y ${url}
  crb enable # this is in epel-release, can only install epel-release via url
  dnf copr enable -y slp/mesa-krunkit epel-9-${uname_m}
  url="https://mirror.stream.centos.org/9-stream/AppStream/${uname_m}/os/"
  dnf config-manager --add-repo ${url}
  url="http://mirror.centos.org/centos/RPM-GPG-KEY-CentOS-Official"
  curl --retry 8 --retry-all-errors -o /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Official ${url}
  rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Official
  dnf --enablerepo=ubi-9-appstream-rpms install -y mesa-vulkan-drivers ${packages[@]}
}

main() {
  set -ex

  local containerfile=${1}
  local install_prefix
  local package_list
  local whisper_cpp_sha=${WHISPER_CPP_SHA:-8a9ad7844d6e2a10cddf4b92de4089d7ac2b14a9}
  local llama_cpp_sha=${LLAMA_CPP_SHA:-aa6fb1321333fae8853d0cdc26bcb5d438e650a1}
  local common_rpms=("python3" "python3-pip" "python3-argcomplete" "python3-dnf-plugin-versionlock" "gcc-c++" "cmake" "vim" "procps-ng" "git" "dnf-plugins-core" "libcurl-devel")
  local vulkan_rpms=("vulkan-headers" "vulkan-loader-devel" "vulkan-tools" "spirv-tools" "glslc" "glslang")
  local intel_rpms=("intel-oneapi-mkl-sycl-devel" "intel-oneapi-dnnl-devel" "intel-oneapi-compiler-dpcpp-cpp" "intel-level-zero" "oneapi-level-zero" "oneapi-level-zero-devel" "intel-compute-runtime")
  local cmake_flags=("-DGGML_CCACHE=OFF" "-DGGML_NATIVE=OFF" "-DBUILD_SHARED_LIBS=NO")

  case ${containerfile} in
    ramalama)
      dnfInstallUbi (${common_rpms[@]} ${vulkan_rpms[@]})
      cmake_flags+=("-DGGML_KOMPUTE=ON" "-DKOMPUTE_OPT_DISABLE_VULKAN_VERSION_CHECK=ON")
      install_prefix=/usr
    ;;
    rocm)
      dnfInstallUbi (${common_rpms[@]} ${vulkan_rpms[@]})
      dnf install -y rocm-dev hipblas-devel rocblas-devel
      cmake_flags+=("-DGGML_HIP=ON" "-DAMDGPU_TARGETS=${AMDGPU_TARGETS:-gfx1010,gfx1030,gfx1032,gfx1100,gfx1101,gfx1102}")
      install_prefix=/usr
    ;;
    cuda)
      dnf install -y "${common_rpms[@]}" gcc-toolset-12
      . /opt/rh/gcc-toolset-12/enable
      cmake_flags+=("-DGGML_CUDA=ON" "-DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined")
      install_prefix=/llama-cpp
    ;;
    vulkan)
      dnfInstallUbi (${common_rpms[@]} ${vulkan_rpms[@]})
      cmake_flags+=("-DGGML_VULKAN=1")
      install_prefix=/usr
    ;;
    asahi)
      dnf copr enable -y @asahi/fedora-remix-branding
      dnf install -y asahi-repos
      dnf install -y mesa-vulkan-drivers "${vulkan_rpms[@]}" "${common_rpms[@]}"
      cmake_flags+=("-DGGML_VULKAN=1")
      install_prefix=/usr
    ;;
    intel-gpu)
      dnf install -y ${common_rpms[@]} ${intel_rpms[@]}
      cmake_flags+=("-DGGML_SYCL=ON" "-DCMAKE_C_COMPILER=icx" "-DCMAKE_CXX_COMPILER=icpx")
      install_prefix=/llama-cpp
    ;;
  esac

  cloneAndBuild https://github.com/ggerganov/whisper.cpp ${whisper_cpp_sha} ${cmake_flags} ${install_prefix}
  cmake_flags+=("-DLLAMA_CURL=ON")
  cloneAndBuild https://github.com/ggerganov/llama.cpp ${llama_cpp_sha} ${cmake_flags} ${install_prefix}
  dnf -y clean all
  rm -rf /var/cache/*dnf* /opt/rocm-*/lib/*/library/*gfx9*
  ldconfig # needed for libraries

}

main "$@"
