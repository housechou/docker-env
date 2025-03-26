#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

#######################################################################
#                           CONFIGURATIONS                            #
#######################################################################
DOCKER_BASE_IMAGE="ubuntu:22.04"
# DNS configuration, keep empty to skip
DNS_SERVER="10.28.42.11"
# HOST_TFTPBOOT is designed as a shared folder between host and docker, keep empty to skip
HOST_TFTPBOOT="/tftpboot"
# SSH_DIR allow you to use the same ssh key in host, it's useful for git over ssh
SSH_DIR="$HOME/.ssh"
# Default Dockerfile path
DOCKERFILE_PATH="./Dockerfile"

# Ensure consistent path handling
HOST_WORKSPACE=$(cd "$(dirname "$0")"/.. && pwd)
TOPDIR_NAME=$(basename "$HOST_WORKSPACE")
# remove leading /
HOST_WORKSPACE_NAME="${HOST_WORKSPACE#/}"
# replace / with _
HOST_WORKSPACE_NAME="${HOST_WORKSPACE_NAME//\//_}"
DOCKER_IMAGE_NAME="${HOST_WORKSPACE_NAME}-${DOCKER_BASE_IMAGE//[:\/]/-}"
CONTAINER_NAME="${HOST_WORKSPACE_NAME}-builder"
DOCKER_WORKSPACE="/work/${TOPDIR_NAME}"

ARG_USER=$(whoami)
ARG_UID=$(id -u)
ARG_WORKSAPCE="${DOCKER_WORKSPACE}"
ARG_TIMEZONE="/usr/share/zoneinfo/Asia/Taipei"
ARG_BASE_IMAGE="$DOCKER_BASE_IMAGE"

DOCKER_CONTAINER_HOSTNAME="${CONTAINER_NAME}"

: "${DOCKER_LINES:=24}"
: "${DOCKER_COLUMNS:=280}"

# Default options
OPT_CLEAN_IMAGE=false

#######################################################################
#                            FUNCTIONS                                #
#######################################################################
usage() {
  cat << EOF
Usage: $(basename "$0") [options]

Options:
  -h, --help              Show this help message
  -c, --clean             Clean old Docker image before building
  -f, --dockerfile <FILE> Specify path to Dockerfile (default: ./Dockerfile)
  -d, --dns <DNS>         Specify dns server for docker
EOF
  exit 0
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        ;;
      -c|--clean)
        OPT_CLEAN_IMAGE=true
        shift
        ;;
      -f|--dockerfile)
        if [[ -z "$2" || "$2" == -* ]]; then
          echo "Error: Dockerfile path missing after $1" >&2
          exit 1
        fi
        DOCKERFILE_PATH="$2"
        shift 2
        ;;
      -d|--dns)
        if [[ -z "$2" || "$2" == -* ]]; then
          echo "Error: have to give dns server after $1" >&2
          exit 1
        fi
        DNS_SERVER="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done
}

check_docker_installed() {
  if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is NOT installed." >&2
    echo "Check https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository" >&2
    exit 1
  fi
}

check_dockerfile_exists() {
  if [[ ! -f "$DOCKERFILE_PATH" ]]; then
    echo "ERROR: Dockerfile not found at $DOCKERFILE_PATH" >&2
    exit 1
  fi
}

check_docker_privileges() {
  if groups | grep -q '\bdocker\b'; then
    DOCKER_CMD="docker"
  else
    DOCKER_CMD="sudo docker"
    echo "Warning: Running docker as \"root\", you can add user to docker group to prevent dangerous" >&2
    echo "  ex: sudo groupadd docker;sudo usermod -aG docker $USER;newgrp docker" >&2
  fi
}

check_ssh_directory() {
  if [ -d "$SSH_DIR" ]; then
    MOUNT_SSH="--mount type=bind,source=$SSH_DIR,target=/home/${ARG_USER}/.ssh"
  else
    MOUNT_SSH=""
    echo "Warning: SSH directory '$SSH_DIR' not found, SSH mount disabled" >&2
  fi
}

check_tftpboot_directory() {
  if [ -n "$HOST_TFTPBOOT" ]; then
    if [ -d "$HOST_TFTPBOOT" ]; then
      MOUNT_TFTPBOOT="--mount type=bind,source=${HOST_TFTPBOOT},target=/tftpboot"
    else
      echo "Warning: TFTPBOOT directory '$HOST_TFTPBOOT' not found, mount disabled" >&2
      MOUNT_TFTPBOOT=""
    fi
  else
    MOUNT_TFTPBOOT=""
  fi
}

check_dns_server() {
  if [ -n "$DNS_SERVER" ]; then
    DNS_OPTION="--dns ${DNS_SERVER}"
    echo "Using DNS server: $DNS_SERVER"
  else
    DNS_OPTION=""
  fi
}

cleanup_container() {
  echo "Cleaning up container ${CONTAINER_NAME}"
  $DOCKER_CMD rm "${CONTAINER_NAME}" || true
}

clean_docker_image() {
  if $OPT_CLEAN_IMAGE; then
    echo "Removing old Docker image: $DOCKER_IMAGE_NAME"
    $DOCKER_CMD rmi "$DOCKER_IMAGE_NAME" || true
  fi
}

check_docker_status() {
  # Check if image exists
  DOCKER_IMAGE=$($DOCKER_CMD images -q "$DOCKER_IMAGE_NAME" 2>/dev/null || true)
  # Check if container exists
  CONTAINER_ID=$($DOCKER_CMD ps -a --format '{{.Names}}' |grep -Fx "${CONTAINER_NAME}" 2>/dev/null || true)
}

build_docker_image() {
  echo "Building Docker image from Dockerfile"
  $DOCKER_CMD build \
    --build-arg BASE_IMAGE="$ARG_BASE_IMAGE" \
    --build-arg workspace="$ARG_WORKSAPCE" \
    --build-arg user="$ARG_USER" \
    --build-arg uid="$ARG_UID" \
    --build-arg timezone="$ARG_TIMEZONE" \
    -t "$DOCKER_IMAGE_NAME" \
    -f "$DOCKERFILE_PATH" \
    "$(dirname "$DOCKERFILE_PATH")"
}

run_docker_container() {
  echo "Starting container"
  $DOCKER_CMD run -t -i --rm -h "${DOCKER_CONTAINER_HOSTNAME}" --name "${CONTAINER_NAME}" \
  --mount type=bind,source="${HOME}",target="/home/${ARG_USER}" \
  --mount type=bind,source="${HOST_WORKSPACE}",target="${DOCKER_WORKSPACE}" \
  $MOUNT_TFTPBOOT \
  $MOUNT_SSH \
  $DNS_OPTION \
  --env "LINES=$DOCKER_LINES" --env "COLUMNS=$DOCKER_COLUMNS" \
  --security-opt seccomp:unconfined \
  "${DOCKER_IMAGE_NAME}"
}

main() {
  # Parse arguments before any function
  parse_arguments "$@"
  
  # Check prerequisites
  check_docker_installed
  check_dockerfile_exists
  check_docker_privileges
  check_ssh_directory
  check_tftpboot_directory
  check_dns_server
  check_docker_status
  
  # Handle clean option
  if $OPT_CLEAN_IMAGE; then
    clean_docker_image
    DOCKER_IMAGE=""  # Force rebuild after clean
  fi

  # Main workflow
  if [ -n "${CONTAINER_ID}" ]; then
    echo "Attaching to previous container"
    if ! $DOCKER_CMD exec --env "LINES=$DOCKER_LINES" --env "COLUMNS=$DOCKER_COLUMNS" -it "${CONTAINER_ID}" bash; then
      echo "Container may be in a bad state. Removing it..." >&2
      cleanup_container
      exit 1
    fi
  elif [ -n "${DOCKER_IMAGE}" ]; then
    if ! run_docker_container; then
      echo "Failed to run container" >&2
      exit 1
    fi
  else
    echo "Building new Docker image: $DOCKER_IMAGE_NAME"
    if ! build_docker_image; then
      echo "Failed to build Docker image" >&2
      exit 1
    fi
    # After successful build, run the container
    if ! run_docker_container; then
      echo "Failed to run container" >&2
      exit 1
    fi
  fi
}

# Run the main function with all arguments
main "$@"
