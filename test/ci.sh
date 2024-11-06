#!/bin/bash

available() {
  command -v "$1" > /dev/null
}

mac_steps() {
  ./install.sh
}

linux_steps() {
  shellcheck -- *.sh */*.sh */*/*.sh
  if [ -n "$BRANCH" ]; then
    $maybe_sudo BRANCH="$BRANCH" ./install.sh
    return
  fi

  $maybe_sudo ./install.sh
}

main() {
  set -ex -o pipefail

  local maybe_sudo=""
  if [ "$EUID" -ne 0 ]; then
    maybe_sudo="sudo"
  fi

  # verify pyproject.toml and setup.py have same version
  grep "$(grep "^version =.*" pyproject.toml)" setup.py

  # verify llama.cpp version matches
  grep "$(grep "ARG LLAMA_CPP_SHA=" container-images/ramalama/Containerfile)" \
    container-images/cuda/Containerfile
  grep "$(grep "ARG LLAMA_CPP_SHA=" container-images/ramalama/Containerfile)" \
    container-images/asahi/Containerfile

  local os
  os="$(uname -s)"
  binfile=bin/ramalama
  chmod +x ${binfile} install.sh
  uname -a
  /usr/bin/python3 --version

  export BRANCH="main"
  if false; then # This doesn't work for forked repos, will revisit
    if [ -n "$GITHUB_HEAD_REF" ]; then
      export BRANCH="$GITHUB_HEAD_REF"
    elif [ -n "$GITHUB_REF_NAME" ]; then
      export BRANCH="$GITHUB_REF_NAME"
    fi
  fi

  if [ "$os" == "Darwin" ]; then
    mac_steps
  else
    linux_steps
  fi

  $maybe_sudo rm -rf /usr/share/ramalama /opt/homebrew/share/ramalama /usr/local/share/ramalama
  go install github.com/cpuguy83/go-md2man@latest
  tmpdir=$(mktemp -d)
  make install DESTDIR="$tmpdir" PREFIX=/usr
  find "$tmpdir"
  rm -rf "$tmpdir"
}

main
