#!/usr/bin/env bash
# Exit on error, and print commands
set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ROOT_DIR=$(dirname "$SCRIPT_DIR")

if ! command -v sudo &> /dev/null; then
  # in docker build sudo isn't avaiable, but its ok
  echo "Warning: sudo could not be found, you may need to run this script with sudo"
  function sudo { "$@"; }
  export -f sudo
fi

# Use CONDA_ENV_NAME if provided, otherwise default to "hssim"
CONDA_ENV_NAME=${CONDA_ENV_NAME:-hsretargeting}
echo "conda environment name is set to: $CONDA_ENV_NAME"

# Create overall workspace
source ${SCRIPT_DIR}/source_common.sh
ENV_ROOT=$CONDA_ROOT/envs/$CONDA_ENV_NAME
SENTINEL_FILE=${WORKSPACE_DIR}/.env_setup_retargeting_$CONDA_ENV_NAME
echo "SENTINEL_FILE: $SENTINEL_FILE"

mkdir -p $WORKSPACE_DIR

if [[ ! -f $SENTINEL_FILE ]]; then
  # Install miniconda
  if [[ ! -d $CONDA_ROOT ]]; then
    mkdir -p $CONDA_ROOT

    # Detect OS and arch
    OS_NAME="$(uname -s)"
    ARCH_NAME="$(uname -m)"

    # Decide installer name based on OS/arch
    if [[ "$OS_NAME" == "Linux" ]]; then
      MINICONDA_INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
    elif [[ "$OS_NAME" == "Darwin" ]]; then
      if [[ "$ARCH_NAME" == "arm64" ]]; then
        # Apple Silicon
        MINICONDA_INSTALLER="Miniconda3-latest-MacOSX-arm64.sh"
      else
        # Intel Mac
        MINICONDA_INSTALLER="Miniconda3-latest-MacOSX-x86_64.sh"
      fi
    else
      echo "Unsupported OS: $OS_NAME"
      exit 1
    fi

    curl "https://repo.anaconda.com/miniconda/${MINICONDA_INSTALLER}" -o "$CONDA_ROOT/miniconda.sh"
    bash $CONDA_ROOT/miniconda.sh -b -u -p $CONDA_ROOT
    rm $CONDA_ROOT/miniconda.sh
  fi

  # Create the conda environment
  if [[ ! -d $ENV_ROOT ]]; then
    $CONDA_ROOT/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
    $CONDA_ROOT/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
    # Solve with libmamba, conda's own default solver, instead of installing mamba into base:
    # that install pulls conda-forge's conda into base and breaks the bundled ToS plugin.
    $CONDA_ROOT/bin/conda create -y --solver libmamba -n $CONDA_ENV_NAME python=3.11 -c conda-forge --override-channels
  fi

  source $CONDA_ROOT/bin/activate $CONDA_ENV_NAME

  # Install holosoma_retargeting
  #pip install -U pip
  #pip install -e $ROOT_DIR/src/holosoma_retargeting
  
  # 1. 安装/更新 uv
  pip install uv -i https://pypi.tuna.tsinghua.edu.cn/simple

  # 2. 将 Conda 环境伪装为标准 Virtualenv，防止 uv 抛出环境隔离保护错误
  export VIRTUAL_ENV=$CONDA_PREFIX

  # 3. 使用 uv 进行多线程并发安装
  uv pip install -e "$ROOT_DIR/src/holosoma_retargeting" \
    --index-url https://pypi.tuna.tsinghua.edu.cn/simple
  touch $SENTINEL_FILE
fi
