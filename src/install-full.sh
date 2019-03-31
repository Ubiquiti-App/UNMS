#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PATH="${PATH}:/usr/local/bin"

UNMS_HTTP_PORT="8081"
UNMS_WS_PORT="8082"
UNMS_WS_SHELL_PORT="8083"
UNMS_WS_API_PORT="8084"
ALTERNATIVE_HTTP_PORT="8080"
ALTERNATIVE_HTTPS_PORT="8443"
ALTERNATIVE_NETFLOW_PORT="2056"


COMPOSE_PROJECT_NAME="unms"
USERNAME=${UNMS_USER:-"unms_ct"}
if getent passwd ${USERNAME} >/dev/null; then
  HOME_DIR="$(getent passwd ${USERNAME} | cut -d: -f6)"
else
  HOME_DIR=${UNMS_HOME_DIR:-"/home/${USERNAME}"}
fi

APP_DIR="${HOME_DIR}/app"
DATA_DIR="${HOME_DIR}/data"
RESTORE_DIR="${DATA_DIR}/unms-backups/restore"
CONFIG_DIR="${APP_DIR}/conf"
CONFIG_FILE="${APP_DIR}/unms.conf"
DOCKER_COMPOSE_INSTALL_PATH="/usr/local/bin"
DOCKER_COMPOSE_FILENAME="docker-compose.yml"
DOCKER_COMPOSE_FILE="${APP_DIR}/${DOCKER_COMPOSE_FILENAME}"
DOCKER_COMPOSE_TEMPLATE_FILENAME="docker-compose.yml.template"
DOCKER_COMPOSE_TEMPLATE="${APP_DIR}/${DOCKER_COMPOSE_TEMPLATE_FILENAME}"

# random key for secure link module
SECURE_LINK_SECRET=$(export LC_ALL=C; head -c 500 /dev/urandom | tr -dc A-Za-z0-9 | head -c 100)

# prerequisites "command|package"
PREREQUISITES=(
  "curl|curl"
  "sed|sed"
  "envsubst|gettext-base"
)

if [ "${SCRIPT_DIR}" = "${APP_DIR}" ]; then
  echo >&2 "Please don't run the installation script in the application directory ${APP_DIR}"
  exit 1
fi

# parse arguments
VERSION="latest"
DEMO="false"
NODE_ENV="production"
USE_LOCAL_IMAGES="false"
DOCKER_IMAGE="ubnt/unms"
DOCKER_USERNAME=""
DOCKER_PASSWORD=""
HTTP_PORT="80"
HTTPS_PORT="443"
WS_PORT=""
NETFLOW_PORT="2055"
PROXY_HTTPS_PORT=""
PROXY_WS_PORT=""
SSL_CERT_DIR=""
SSL_CERT=""
SSL_CERT_KEY=""
SSL_CERT_CA=""
HOST_TAG=""
UNATTENDED="false"
NO_AUTO_UPDATE="false"
NO_OVERCOMMIT_MEMORY="false"
BRANCH="master"
SUBNET=""
CLUSTER_SIZE=auto

fail() {
  echo -e "ERROR: $1" >&2
  exit 1
}

read_previous_config() {
  # read WS port settings from existing running container
  # they were not saved to config file in versions <=0.7.18
  if ! oldEnv=$(docker inspect --format '{{ .Config.Env }}' unms); then
    echo "Couldn't read WS port config from existing UNMS container"
  else
    WS_PORT=$(docker ps --filter "name=unms$" --filter "status=running" --format "{{.Ports}}" | sed -E "s/.*0.0.0.0:([0-9]+)->8444.*|.*/\1/")
    echo "Setting WS_PORT=${WS_PORT}"
    PROXY_WS_PORT=$(echo "${oldEnv}" | sed -E "s/.*[ []PUBLIC_WS_PORT=([0-9]*).*|.*/\1/")
    echo "Setting PROXY_WS_PORT=${PROXY_WS_PORT}"
  fi

  # read config file
  if [ -f "${CONFIG_FILE}" ]; then
    echo "Reading configuration file ${CONFIG_FILE}"
    cat "${CONFIG_FILE}"
    if ! source "${CONFIG_FILE}"; then
      echo >&2 "Failed to read configuration from ${CONFIG_FILE}"
      exit 1
    fi
  else
    echo "Configuration file not found."
  fi
}

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
  --demo)
    echo "Setting DEMO=true"
    DEMO="true"
    ;;
  --update)
    echo "Restoring previous configuration"
    read_previous_config
    ;;
  --unattended)
    echo "Setting UNATTENDED=true"
    UNATTENDED="true"
    ;;
  --no-auto-update)
    echo "Setting NO_AUTO_UPDATE=true"
    NO_AUTO_UPDATE="true"
    ;;
  --no-overcommit-memory)
    echo "Setting NO_OVERCOMMIT_MEMORY=true"
    NO_OVERCOMMIT_MEMORY="true"
    ;;
  --use-local-images)
    echo "Setting USE_LOCAL_IMAGES=true"
    USE_LOCAL_IMAGES="true"
    ;;
  -v|--version)
    echo "Setting VERSION=$2"
    VERSION="$2"
    shift # past argument value
    ;;
  --docker-image)
    echo "Setting DOCKER_IMAGE=$2"
    DOCKER_IMAGE="$2"
    shift # past argument value
    ;;
  --docker-username)
    echo "Setting DOCKER_USERNAME=$2"
    DOCKER_USERNAME="$2"
    shift # past argument value
    ;;
  --docker-password)
    echo "Setting DOCKER_PASSWORD=*****"
    DOCKER_PASSWORD="$2"
    shift # past argument value
    ;;
  --data-dir)
    echo "Setting DATA_DIR=$2"
    DATA_DIR="$2"
    shift # past argument value
    ;;
  --http-port)
    echo "Setting HTTP_PORT=$2"
    HTTP_PORT="$2"
    shift # past argument value
    ;;
  --https-port)
    echo "Setting HTTPS_PORT=$2"
    HTTPS_PORT="$2"
    shift # past argument value
    ;;
  --ws-port)
    echo "Setting WS_PORT=$2"
    WS_PORT="$2"
    shift # past argument value
    ;;
  --public-https-port)
    echo "Setting PROXY_HTTPS_PORT=$2"
    PROXY_HTTPS_PORT="$2"
    shift # past argument value
    ;;
  --public-ws-port)
    echo "Setting PROXY_WS_PORT=$2"
    PROXY_WS_PORT="$2"
    shift # past argument value
    ;;
  --netflow-port)
    echo "Setting NETFLOW_PORT=$2"
    NETFLOW_PORT="$2"
    shift # past argument value
    ;;
  --ssl-cert-dir)
    echo "Setting SSL_CERT_DIR=$2"
    SSL_CERT_DIR="$2"
    shift # past argument value
    ;;
  --ssl-cert)
    echo "Setting SSL_CERT=$2"
    SSL_CERT="$2"
    shift # past argument value
    ;;
  --ssl-cert-key)
    echo "Setting SSL_CERT_KEY=$2"
    SSL_CERT_KEY="$2"
    shift # past argument value
    ;;
  --ssl-cert-ca)
    echo "Setting SSL_CERT_CA=$2"
    SSL_CERT_CA="$2"
    shift # past argument value
    ;;
  --host-tag)
    echo "Setting HOST_TAG=$2"
    HOST_TAG="$2"
    shift # past argument value
    ;;
  --branch)
    echo "Setting BRANCH=$2"
    BRANCH="$2"
    shift # past argument value
    ;;
  --subnet)
    echo "Setting SUBNET=$2"
    SUBNET="$2"
    shift # past argument value
    ;;
  --node-env)
    echo "Setting NODE_ENV=$2"
    NODE_ENV="$2"
    shift # past argument value
    ;;
  --workers)
    echo "Setting CLUSTER_SIZE=$2"
    [[ "${2}" =~ ^[1-8]$ ]] || [[ "${2}" = "auto" ]] || fail "--workers argument must be a number in range 1-8 or 'auto'."
    CLUSTER_SIZE="$2"
    ;;

  *)
    # unknown option
    ;;
esac
shift # past argument key
done

# check that none or all three SSL variables are set
if [ ! -z "${SSL_CERT_DIR}" ] || [ ! -z "${SSL_CERT}" ] || [ ! -z "${SSL_CERT_KEY}" ]; then
  if [ -z "${SSL_CERT_DIR}" ]; then echo >&2 "Please set --ssl-cert-dir"; exit 1; fi
  if [ -z "${SSL_CERT}" ]; then echo >&2 "Please set --ssl-cert"; exit 1; fi
  if [ -z "${SSL_CERT_KEY}" ]; then echo >&2 "Please set --ssl-cert-key"; exit 1; fi
fi

# check subnet and prepare the networks section of docker compose file
IPAM_PUBLIC=""
IPAM_PRIVATE=""
if [ ! -z "${SUBNET}" ]; then
  cidrRegex="^([0-9]{1,3}\.){3}[0-9]{1,3}(\/([0-9]|[1-2][0-9]|3[0-2]))?$"

  if [[ ! "${SUBNET}" =~ ${cidrRegex} ]]; then
    echo >&2 "Value of --subnet is invalid. Please use CIDR notation (ex. 172.45.0.1/24)"
    exit 1
  fi

  IFS=/ read -r subnetIp subnetPrefix <<< "${SUBNET}"
  if [ "${subnetPrefix}" -gt 27 ]; then
    echo >&2 Please specify a subnet with 32 or more addresses
    exit 1
  fi

  dec2ip () {
    local ip dec=$@ delim=""
    for e in {3..0}; do
      ((octet = dec / (256 ** e) ))
      ((dec -= octet * 256 ** e))
      ip+=$delim$octet
      delim=.
    done
    printf '%s\n' "$ip"
  }

  ip2dec () {
    local a b c d ip=$@
    IFS=. read -r a b c d <<< "$ip"
    printf '%d\n' "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
  }

  # split subnet into privateSubnet and publicSubnet
  subnetIpDec=$( ip2dec "${subnetIp}" )
  subnetMask=$(( 0xffffffff - 2 ** ( 32 - ${subnetPrefix} ) + 1 ))
  subnetIpMaskedDec=$(( ${subnetIpDec} & ${subnetMask} ))

  newSubnetPrefix=$(( ${subnetPrefix} + 1 ))
  publicSubnetIpDec=$(( ${subnetIpMaskedDec} + 1 ))
  privateSubnetIpDec=$(( ${subnetIpMaskedDec} + 1 + 2**(32 - ${newSubnetPrefix}) ))

  publicSubnetIp=$(dec2ip "${publicSubnetIpDec}")
  privateSubnetIp=$(dec2ip "${privateSubnetIpDec}")

  # prepare subnet section of the docker compose file
  IPAM_PUBLIC=$(printf "ipam:\n      config:\n        - subnet: \"${publicSubnetIp}/${newSubnetPrefix}\"")
  IPAM_PRIVATE=$(printf "ipam:\n      config:\n        - subnet: \"${privateSubnetIp}/${newSubnetPrefix}\"")
fi

# prepare --silent option for curl
curlSilent=""
if [ "${UNATTENDED}" = "true" ]; then
  curlSilent="--silent"
fi


export COMPOSE_PROJECT_NAME
export VERSION
export DEMO
export NODE_ENV
export DOCKER_IMAGE
export DATA_DIR
export CONFIG_DIR
export HTTP_PORT
export HTTPS_PORT
export WS_PORT
export WS_SHELL_PORT
export NETFLOW_PORT
export SSL_CERT
export SSL_CERT_KEY
export SSL_CERT_CA
export HOST_TAG
export BRANCH
export UNMS_HTTP_PORT
export UNMS_WS_PORT
export UNMS_WS_SHELL_PORT
export UNMS_WS_API_PORT
export SECURE_LINK_SECRET
export IPAM_PUBLIC
export IPAM_PRIVATE
export CLUSTER_SIZE

is_decimal_number() {
  [[ ${1} =~ ^[0-9]+$ ]]
}

version_equal_or_newer() {
  if [[ "$1" == "$2" ]]; then return 0; fi
  local IFS=.
  local i ver1=($1) ver2=($2)
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
  for ((i=0; i<${#ver1[@]}; i++)); do
    if [[ -z ${ver2[i]} ]]; then ver2[i]=0; fi
    if ! is_decimal_number "${ver1[i]}" ; then return 1; fi
    if ! is_decimal_number "${ver2[i]}" ; then return 1; fi
    if ((10#${ver1[i]} > 10#${ver2[i]})); then return 0; fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then return 1; fi
  done
  return 0;
}

# usage: confirm <question>
# Prints given question and asks user to type Y or N.
# Returns 0 if user typed Y, 1 if user typed N.
# Exits if user failed to type Y or N too many times.
# examples:
# confirm "Do you want to continue?" || exit 1
confirm() {
  local question="$1"
  for i in {0..10}; do
    read -p "${question} [Y/N]" -n 1 -r
    echo
    if [[ ${REPLY} =~ ^[Yy]$ ]]; then
      echo "Yes"
      return 0
    fi
    if [[ ${REPLY} =~ ^[Nn]$ ]]; then
      echo "No"
      return 1
    fi
    echo "Please type Y or N."
  done
  echo "Too many failed attempts."
  exit 1
}

check_system() {
  local architecture
  architecture=$(uname -m)
  case "${architecture}" in
    amd64|x86_64)
      ;;
    *)
      echo >&2 "Unsupported platform '${architecture}'."
      echo >&2 "UNMS supports: x86_64/amd64."
      exit 1
      ;;
  esac

  local lsb_dist
  local dist_version

  if [ -z "${lsb_dist:-}" ] && [ -r /etc/lsb-release ]; then
      lsb_dist="$(. /etc/lsb-release && echo "${DISTRIB_ID:-}")"
  fi

  if [ -z "${lsb_dist:-}" ] && [ -r /etc/debian_version ]; then
      lsb_dist="debian"
  fi

  if [ -z "${lsb_dist:-}" ] && [ -r /etc/fedora-release ]; then
      lsb_dist="fedora"
  fi

  if [ -z "${lsb_dist:-}" ] && [ -r /etc/oracle-release ]; then
      lsb_dist="oracleserver"
  fi

  if [ -z "${lsb_dist:-}" ]; then
      if [ -r /etc/centos-release ] || [ -r /etc/redhat-release ]; then
      lsb_dist="centos"
      fi
  fi

  if [ -z "${lsb_dist:-}" ] && [ -r /etc/os-release ]; then
      lsb_dist="$(. /etc/os-release && echo "${ID:-}")"
  fi

  lsb_dist="$(echo "${lsb_dist:-}" | tr '[:upper:]' '[:lower:]')"

  supported_distro=false
  case "${lsb_dist}" in

      ubuntu)
      if [ -z "${dist_version:-}" ] && [ -r /etc/lsb-release ]; then
          dist_version="$(. /etc/lsb-release && echo "${DISTRIB_RELEASE:-}")"
      fi
      if version_equal_or_newer "${dist_version}" "16.04"; then
        supported_distro=true
      fi
      ;;

      debian)
      dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
      case "${dist_version}" in
        jessie) dist_version=8;;
        stretch) dist_version=9;;
        buster) dist_version=10;;
      esac
      if version_equal_or_newer "${dist_version}" "8"; then
        supported_distro=true
      fi
      ;;

      *coreos)
      if [ -z "${dist_version:-}" ] && [ -r /etc/lsb-release ]; then
          dist_version="$(. /etc/lsb-release && echo "${DISTRIB_RELEASE:-}")"
      fi
      if version_equal_or_newer "${dist_version}" "1465.6.0"; then
        if ! echo $PATH | grep -q "/opt/bin" ; then
            export PATH="/opt/bin:$PATH"
        fi

        if [ ! -d /opt/bin ]; then
          mkdir -p /opt/bin
        fi

        DOCKER_COMPOSE_INSTALL_PATH="/opt/bin"

        supported_distro=true
      fi
      ;;

      *)
      if [ -z "${dist_version:-}" ] && [ -r /etc/os-release ]; then
        dist_version="$(. /etc/os-release && echo "${VERSION_ID:-}")"
      fi
      ;;

  esac

  for prerequisite in "${PREREQUISITES[@]}"; do
    IFS=\| read -r preCommand prePackage <<< "${prerequisite}"
    command -v "${preCommand}" >/dev/null 2>&1 || {
      echo >&2 "This script requires '${preCommand}'. Please install '${prePackage}' and try again. Aborting."
      exit 1
    }
  done

  if [ ! "$UNATTENDED" = true ] && [ ! "${supported_distro}" = true ]; then
    echo "Your distribution '${lsb_dist} ${dist_version:-}' is not supported."
    echo "We recommend that you install UNMS on Ubuntu 16.04, Debian 9 or newer."
    confirm "Would you like to continue with the installation anyway?" || exit 1
  fi

  if [ ! "$UNATTENDED" = true ] && [[ -e /proc/meminfo ]]; then
    local memory
    local memoryUnit
    memory="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
    if (which bc > /dev/null 2>&1); then
      memoryUnit=$(echo "scale=2; ${memory}/1024^2" | bc)
      memoryUnit="${memoryUnit} GB"
    else
      memoryUnit="${memory} KB"
    fi

    if [[ "${memory}" -lt 1000000 ]]; then
      echo >&2 "ERROR: Your system has only ${memoryUnit} of RAM."
      echo >&2 "UNMS requires at least 1 GB of RAM to run and 2 GB is recommended. Installation aborted."
      exit 1
    fi

    if [[ "${memory}" -lt 2000000 ]]; then
      echo >&2 "WARNING: Your system has only ${memoryUnit} RAM."
      echo >&2 "We recommend at least 2 GB RAM to run UNMS without problems."
    fi
  fi
}

check_custom_cert_path() {
  if [ -z "${SSL_CERT_DIR}" ]; then
    # Not using custom cert.
    return 0
  fi
  if [ "${EUID}" -ne 0 ]; then
    # Ignore cert check during update.
    return 0
  fi

  local cert_path="${SSL_CERT_DIR}/${SSL_CERT}"
  local key_path="${SSL_CERT_DIR}/${SSL_CERT_KEY}"
  local norm_cert_dir
  local norm_cert_path
  local norm_key_path

  # Check that cert and key files exist.
  test -f "${cert_path}" || fail "Cert file '${cert_path}' does not exist. Check the --ssl-cert-dir and --ssl-cert arguments."
  test -f "${key_path}" || fail "Key file '${key_path}' does not exist. Check the --ssl-cert-dir and --ssl-cert-key arguments."

  # Check that the cert dir is parent of cert and key files.
  # Nginx container mounts this directory and if the cert or key file actually placed within another directory it will
  # be inaccessible from within the container.
  norm_cert_dir=$(readlink -f "${SSL_CERT_DIR}") || fail "Failed to determine real path of cert directory '${SSL_CERT_DIR}'. Check the --ssl-cert-dir argument."
  norm_cert_path=$(readlink -f "${cert_path}") || fail "Failed to determine real path of cert file '${cert_path}'. Check the --ssl-cert argument."
  norm_key_path=$(readlink -f "${key_path}") || fail "Failed to determine real path of key file '${key_path}'. Check the --ssl-cert-key argument."
  [[ "${norm_cert_path}" = "${norm_cert_dir}"* ]] || fail "Cert file: \n${norm_cert_path}\n is not placed in the cert directory:\n${norm_cert_dir}\nCheck --ssl-cert-dir and --ssl-cert arguments for symbolic links. The actual ssl cert file (not just symbolic link) must be within the ssl cert directory or its subdirectories."
  [[ "${norm_key_path}" = "${norm_cert_dir}"* ]] || fail "Key file:\n${norm_key_path}\n is not placed in the cert directory:\n${norm_cert_dir}\nCheck --ssl-cert-dir and --ssl-cert-key arguments for symbolic links. The actual ssl key file (not just symbolic link) must be within the ssl cert directory or its subdirectories."
}

install_docker() {
  if ! which docker > /dev/null 2>&1; then
    echo "Download and install Docker"
    (
      unset VERSION # we use this for UNMS version, docker thinks it is the docker version
      export CHANNEL="stable"
      curl -fsSL https://get.docker.com/ | sh
    )

    systemctl enable docker
    systemctl start docker
  fi

  DOCKER_VERSION=$(docker -v | sed 's/.*version \([0-9.]*\).*/\1/');
  echo "Docker version: ${DOCKER_VERSION}"
  if ! version_equal_or_newer "${DOCKER_VERSION}" "1.12.4" ; then
    echo "Docker version ${DOCKER_VERSION} is not supported. Please upgrade to version 1.12.4 or newer."
    exit 1;
  fi

  if ! which docker > /dev/null 2>&1; then
    echo >&2 "Docker not installed. Please check previous logs. Aborting."
    exit 1
  fi
}

install_docker_compose() {
  if ! which docker-compose > /dev/null 2>&1; then
    echo "Download and install Docker compose."
    curl -sL "https://github.com/docker/compose/releases/download/1.9.0/docker-compose-$(uname -s)-$(uname -m)" > ${DOCKER_COMPOSE_INSTALL_PATH}/docker-compose
    chmod +x ${DOCKER_COMPOSE_INSTALL_PATH}/docker-compose
  fi

  if ! which docker-compose > /dev/null 2>&1; then
    echo >&2 "Docker compose not installed. Please check previous logs. Aborting."
    exit 1
  fi

  DOCKER_COMPOSE_VERSION=$(docker-compose -v | sed 's/.*version \([0-9]*\.[0-9]*\).*/\1/');
  echo "Docker Compose version: ${DOCKER_COMPOSE_VERSION}"

  if ! version_equal_or_newer "${DOCKER_COMPOSE_VERSION}" "1.9" ; then
    echo >&2 "Docker compose version ${DOCKER_COMPOSE_VERSION} is not supported. Please upgrade to version 1.9 or newer."
    if [ "$UNATTENDED" = true ]; then exit 1; fi
    confirm "Would you like to upgrade Docker compose automatically?" || exit 1
    if ! curl -sL "https://github.com/docker/compose/releases/download/1.9.0/docker-compose-$(uname -s)-$(uname -m)" -o ${DOCKER_COMPOSE_INSTALL_PATH}/docker-compose; then
      echo >&2 "Docker compose upgrade failed. Aborting."
      exit 1
    fi
    chmod +x ${DOCKER_COMPOSE_INSTALL_PATH}/docker-compose
  fi
}

set_overcommit_memory() {
  if [ "$EUID" -ne 0 ]; then
    echo "Skipping vm.overcommit_memory setting. Not running as root."
    return 0
  fi

  if [ "${NO_OVERCOMMIT_MEMORY}" = true ]; then
    echo "Skipping vm.overcommit_memory setting."
    return 0
  fi

  local currentSetting=0
  currentSetting=$(cat /proc/sys/vm/overcommit_memory)
  if [ "${currentSetting}" = "1" ]; then
    echo "Skipping vm.overcommit_memory setting. It is already set to 1."
    return 0
  fi

  local totalMemoryKb=0
  totalMemoryKb=$(grep "^MemTotal:" /proc/meminfo | sed 's/[^0-9]//g')
  if [ "${totalMemoryKb}" -ge 2097152 ]; then # 2GB in kilobytes
    echo "Skipping vm.overcommit_memory setting. Server has enough memory."
    return 0
  fi

  if [ ! "$UNATTENDED" = true ]; then
    echo "This server has less than 2GB of memory. We recommend setting kernel"
    echo "overcommit memory setting to 1. This improves stability of some docker"
    echo "containers."
    if ! confirm "Would you like to set the overcommit memory setting to 1?"; then
      echo "Skipping vm.overcommit_memory setting."
      return 0
    fi
  fi

  echo "Setting vm.overcommit_memory=1"
  echo "vm.overcommit_memory=1" >> /etc/sysctl.conf
  sysctl -p > /dev/null
}

create_user() {
  if [ -z "$(getent passwd ${USERNAME})" ]; then
    echo "Creating user ${USERNAME}, home dir '${HOME_DIR}'."
    if ! useradd -m -d "${HOME_DIR}" -G docker "${USERNAME}"; then
      echo >&2 "Failed to create user '${USERNAME}'"
      exit 1
    fi
  else
    echo >&2 "WARNING: User '${USERNAME}' already exists. We are going to ensure that the"
    echo >&2 "user is in the 'docker' group and that its home '${HOME_DIR}' dir exists and"
    echo >&2 "is writeable by the user."
    if ! [ "$UNATTENDED" = true ]; then
      confirm "Would you like to continue with the installation?" || exit 1
    fi
  fi

  if ! getent group docker | grep -q "\b${USERNAME}\b"; then
    echo "Adding user '${USERNAME}' to docker group."
    if ! usermod -aG docker "${USERNAME}"; then
      echo >&2 "Failed to add user '${USERNAME}' to docker group."
      exit 1
    fi
  fi

  if ! [ -d "${HOME_DIR}" ]; then
    echo "Creating home directory '${HOME_DIR}'."
    if ! mkdir -p "${HOME_DIR}"; then
      echo >&2 "Failed to create home directory '${HOME_DIR}'."
      exit 1
    fi
  fi

  chown "${USERNAME}" "${HOME_DIR}"
  export USER_ID=$(id -u "${USERNAME}")
}

backup_mongo() {
  if ! docker inspect unms-mongo &> /dev/null; then
    return 0
  fi

  if ! docker exec unms-mongo mongoexport --jsonArray --db unms --collection logs --out /data/db/logs.json; then
    echo >&2 "Failed to export logs from Mongo DB";
    exit 1
  fi
  if ! mv -fT "${DATA_DIR}/mongo/logs.json" "${DATA_DIR}/import/logs.json"; then
    echo >&2 "Failed to export logs from Mongo DB";
    exit 1
  fi

  if ! docker exec -t unms-mongo mongoexport --jsonArray --db unms --collection outages --out /data/db/outages.json; then
    echo >&2 "Failed to export outages from Mongo DB";
    exit 1
  fi
  if ! mv -fT "${DATA_DIR}/mongo/outages.json" "${DATA_DIR}/import/outages.json"; then
    echo >&2 "Failed to export outages from Mongo DB";
    exit 1
  fi

  echo "Stopping unms-mongo"
  docker stop unms-mongo
  echo "Removing unms-mongo"
  docker rm unms-mongo
  echo "Removing ${DATA_DIR}/mongo"
  rm -rf "${DATA_DIR}/mongo"
}

fix_080_permission_issue() {
  testFile="${APP_DIR}/docker-compose.yml"
  containerImage=$(docker ps --filter name=unms$ --format "{{ .Image }}") || true
  targetImage="ubnt/unms:0.8.0"
  tempContainer="unms-temp"
  if [ -f "${testFile}" ] && [ ! -w  "${testFile}" ] && [ "${containerImage}" = "${targetImage}" ]; then
    echo "Fixing 0.8.0 permission issue..."
    docker run --name "${tempContainer}" --entrypoint=/bin/bash -v "${APP_DIR}:/appdir" "${targetImage}" -c "chown -R ${USER_ID} /appdir"
    docker rm "${tempContainer}" || true
  else
    echo "Skipping 0.8.0 permission fix"
  fi
}

remove_old_restore_files() {
  # Make sure that restore dir does not exist. We are now applying any backup in this directory during start
  # of UNMS container. Under normal circumstances this directory should be empty or not exist at all.
  test -d "${RESTORE_DIR}" || return 0 # nothing to delete
  rm "${RESTORE_DIR}" -rf || echo "WARNING: Failed to clear restore directory '${RESTORE_DIR}'."
}

migrate_app_files() {
  oldConfigFile="${HOME_DIR}/unms.conf"
  oldDockerComposeFile="${HOME_DIR}/docker-compose.yml"
  oldDockerComposeTemplate="${HOME_DIR}/docker-compose.yml.template"
  oldConfigDir="${HOME_DIR}/conf"

  mkdir -p -m 700 "${APP_DIR}"

  if [ -f "${oldConfigFile}" ]; then mv -u "${oldConfigFile}" "${CONFIG_FILE}"; fi
  if [ -f "${oldDockerComposeFile}" ]; then mv -u "${oldDockerComposeFile}" "${DOCKER_COMPOSE_FILE}"; fi
  if [ -f "${oldDockerComposeTemplate}" ]; then mv -u "${oldDockerComposeTemplate}" "${DOCKER_COMPOSE_TEMPLATE}"; fi
  if [ -d "${oldConfigDir}" ]; then rm -rf "${oldConfigDir}"; fi

  chown -R "${USERNAME}" "${APP_DIR}" || true
}

prepare_templates() {
  echo "Preparing templates"
  cd "${SCRIPT_DIR}"

  # set home dir in update.sh
  if ! sed -i -- "s|##HOMEDIR##|${HOME_DIR}|g" update.sh; then
    echo >&2 "Failed update home dir in update.sh"
    exit 1
  fi

  # set branch name in update.sh
  if ! sed -i -- "s|##BRANCH##|${BRANCH}|g" update.sh; then
    echo >&2 "Failed update branch name in update.sh"
    exit 1
  fi
}

determine_public_ports() {
  # The docker-compose.yml will be broken if we use same port for http and https. Make sure that they are different.
  if [ "${HTTP_PORT}" = "${HTTPS_PORT}" ]; then
    echo >&2 "ERROR: Port '${HTTP_PORT}' cannot be configured for both http and https. Please choose different ports using --http-port and --https-port arguments"
    exit 1
  fi

  # default for PUBLIC_HTTPS_PORT is HTTPS_PORT
  PUBLIC_HTTPS_PORT="${HTTPS_PORT}"

  # PROXY_HTTPS_PORT overrides PUBLIC_HTTPS_PORT
  if [ ! -z "${PROXY_HTTPS_PORT:-}" ]; then
    PUBLIC_HTTPS_PORT="${PROXY_HTTPS_PORT}"
  fi

  # default for PROXY_WS_PORT is PROXY_HTTPS_PORT
  if [ -z "${PROXY_WS_PORT:-}" ]; then
    PROXY_WS_PORT="${PROXY_HTTPS_PORT}"
  fi

  # default for PUBLIC_WS_PORT is WS_PORT
  PUBLIC_WS_PORT="${WS_PORT}"

  # PROXY_WS_PORT overrides PUBLIC_WS_PORT
  if [ ! -z "${PROXY_WS_PORT:-}" ]; then
    PUBLIC_WS_PORT="${PROXY_WS_PORT}"
  fi

  # if WS port is different from HTTP port, add port mapping
  WS_PORT_MAPPING=
  if [ ! -z "${WS_PORT}" ] && [ ! "${WS_PORT}" = "${HTTPS_PORT}" ]; then
    WS_PORT_MAPPING="- \"${WS_PORT}:${WS_PORT}\""
  fi

  export PUBLIC_HTTPS_PORT
  export PUBLIC_WS_PORT
  export WS_PORT_MAPPING
}

create_docker_compose_file() {
  echo "Creating docker-compose.yml"
  cd "${SCRIPT_DIR}"
  if ! envsubst < "${DOCKER_COMPOSE_TEMPLATE_FILENAME}" > "${DOCKER_COMPOSE_FILENAME}"; then
    echo >&2 "Failed to create docker-compose.yml"
    exit 1
  fi
}

login_to_dockerhub() {
  if [[ ${DOCKER_USERNAME} ]]; then
    echo "Logging in to Docker Hub as ${DOCKER_USERNAME}"
    docker login -u="${DOCKER_USERNAME}" -p="${DOCKER_PASSWORD}"
  fi
}

pull_docker_images() {
  if [ ${USE_LOCAL_IMAGES} = true ]; then
    echo "Will try to use local Docker images."
    return 0
  fi

  echo "Pulling docker images."
  cd "${SCRIPT_DIR}"

  if [ -f "${DOCKER_COMPOSE_FILENAME}" ]; then
    if ! docker-compose pull; then
      echo >&2 "Failed to pull docker images"
      exit 1
    fi
  fi

  docker pull ubnt/ucrm-conntrack || fail "Failed to pull ubnt/ucrm-conntrack image"
}

build_docker_images() {
  echo "Building docker images."
  cd "${SCRIPT_DIR}"

  if [ -f "${DOCKER_COMPOSE_FILENAME}" ]; then
    if ! docker-compose build; then
      echo "Failed to build docker images"
      exit 1
    fi
  fi
}

stop_docker_containers() {
  if [ -f "${DOCKER_COMPOSE_FILE}" ]; then
    echo "Stopping docker containers."
    cd "${APP_DIR}"
    if ! docker-compose down; then
      echo >&2 "Failed to stop docker containers"
      exit 1
    fi
  fi
}

try_to_bind_port() {
  local port="${1}"
  local protocol="${2}" # tcp or udp
  # Try to create docker container that bounds given port.
  docker run --rm -p "${port}:${port}/${protocol}" --entrypoint /bin/echo "${DOCKER_IMAGE}:${VERSION}" "Port ${port}/${protocol} is free." 2>/dev/null
}

check_free_ports() {
  echo "Checking available ports"
  while ! try_to_bind_port "${HTTP_PORT}" "tcp"; do
    test "$UNATTENDED" = "false" || fail "Port ${HTTP_PORT} is in use."
    read -r -p "Port ${HTTP_PORT} is already in use, please choose a different HTTP port for UNMS. [${ALTERNATIVE_HTTP_PORT}]: " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-$ALTERNATIVE_HTTP_PORT}
  done

  while ! try_to_bind_port "${HTTPS_PORT}" "tcp"; do
    test "$UNATTENDED" = "false" || fail "Port ${HTTPS_PORT} is in use."
    read -r -p "Port ${HTTPS_PORT} is already in use, please choose a different HTTPS port for UNMS. [${ALTERNATIVE_HTTPS_PORT}]: " HTTPS_PORT
    HTTPS_PORT=${HTTPS_PORT:-$ALTERNATIVE_HTTPS_PORT}
  done

  while ! try_to_bind_port "${NETFLOW_PORT}" "udp"; do
    if [ "$UNATTENDED" = true ]; then
      echo >&2 "WARNING: Port ${NETFLOW_PORT} is in use. Selecting ${ALTERNATIVE_NETFLOW_PORT} port for NetFlow."
      NETFLOW_PORT="${ALTERNATIVE_NETFLOW_PORT}"
      break
    else
      read -r -p "Port ${NETFLOW_PORT} is already in use, please choose a different NetFlow port for UNMS. [${ALTERNATIVE_NETFLOW_PORT}]: " NETFLOW_PORT
      NETFLOW_PORT=${NETFLOW_PORT:-$ALTERNATIVE_NETFLOW_PORT}
    fi
  done
}

create_data_volumes() {
  echo "Creating data volumes."
  echo  "Will mount ${DATA_DIR}"
  mkdir -p "${DATA_DIR}"

  # some old versions linked data/cert to external cert dir
  if [ -L "${DATA_DIR}/cert" ]; then
    echo "Deleting old symlink ${DATA_DIR}/cert"
    rm -f "${DATA_DIR}/cert";
  fi

  # always mount ~unms/data/cert as /cert
  # mount either an external cert dir or ~unms/data/cert as /usercert
  mkdir -p -m u+rwX,g-rwx,o-rwx "${DATA_DIR}/cert"
  export CERT_DIR_MAPPING_NGINX="- ${DATA_DIR}/cert:/cert"
  if [ -z "${SSL_CERT_DIR}" ]; then
    export USERCERT_DIR_MAPPING_NGINX=""
  else
    echo "Will mount ${SSL_CERT_DIR} as /usercert"
    export USERCERT_DIR_MAPPING_NGINX="- ${SSL_CERT_DIR}:/usercert:ro"
  fi

  # Redis, Postgres, Fluentd
  mkdir -p -m u+rwX,g-rwx,o-rwx "${DATA_DIR}/redis"

  # containers will change permissions at startup where necessary
  chown -R "${USERNAME}" "${DATA_DIR}" || true
}

deploy_templates() {
  echo "Deploying templates"
  cd "${SCRIPT_DIR}"

  # set home dir in update.sh
  if ! sed -i -- "s|##HOMEDIR##|${HOME_DIR}|g" update.sh; then
    echo >&2 "Failed update home dir in update.sh"
    exit 1
  fi

  # set branch name in update.sh
  if ! sed -i -- "s|##BRANCH##|${BRANCH}|g" update.sh; then
    echo >&2 "Failed update branch name in update.sh"
    exit 1
  fi

  mkdir -p "${APP_DIR}"
  if ! cp -r ./* "${APP_DIR}/"; then
    echo >&2 "Failed to deploy templates to ${APP_DIR}"
    exit 1
  fi
}

save_config() {
  echo "Writing config file"
  if ! cat >"${CONFIG_FILE}" <<EOL
VERSION="${VERSION}"
DEMO="${DEMO}"
NODE_ENV="${NODE_ENV}"
DOCKER_IMAGE="${DOCKER_IMAGE}"
DATA_DIR="${DATA_DIR}"
HTTP_PORT="${HTTP_PORT}"
HTTPS_PORT="${HTTPS_PORT}"
NETFLOW_PORT="${NETFLOW_PORT}"
PROXY_HTTPS_PORT="${PROXY_HTTPS_PORT}"
WS_PORT="${WS_PORT}"
PROXY_WS_PORT="${PROXY_WS_PORT}"
SSL_CERT_DIR="${SSL_CERT_DIR}"
SSL_CERT="${SSL_CERT}"
SSL_CERT_KEY="${SSL_CERT_KEY}"
SSL_CERT_CA="${SSL_CERT_CA}"
HOST_TAG="${HOST_TAG}"
BRANCH="${BRANCH}"
SUBNET="${SUBNET}"
CLUSTER_SIZE="${CLUSTER_SIZE}"
EOL
  then
    echo >&2 "Failed to save config file ${CONFIG_FILE}"
    exit 1
  fi
}

setup_auto_update() {
  if [ "$NO_AUTO_UPDATE" = true ] || [ "$EUID" -ne 0 ]; then
    echo "Skipping auto-update setup."
  else
    updateScript="${APP_DIR}/update.sh";

    if ! chmod +x "${updateScript}"; then
      echo >&2 "Failed to setup auto-update script"
      exit 1
    fi

    if [ -d /etc/cron.d ] && which crontab > /dev/null 2>&1; then
      echo "* * * * * ${USERNAME} ${updateScript} --cron > /dev/null 2>&1 || true" > /etc/cron.d/unms-update

      if (crontab -l -u "${USERNAME}" | grep "update.sh --cron"); then
        # The per-user crontab was used in previous versions of UNMS. Now we are using the global crontab.
        # Remove the update script from per-user crontab. There should be no other records by default but
        # user may have set up some custom job so remove just the update script.
        crontab -l -u "${USERNAME}" | grep -v "update.sh --cron" || true | crontab -u "${USERNAME}" -
      fi
    else
      if [ -d /etc/systemd/system ] && which systemctl > /dev/null 2>&1; then

cat > /etc/systemd/system/unms-update.service <<EOL
[Unit]
Description=Auto update UNMS

[Service]
User=${USERNAME}
Type=oneshot
ExecStart=${updateScript} --cron
EOL

cat > /etc/systemd/system/unms-update.timer <<EOL
[Unit]
Description=Run unms-update.service every minute

[Timer]
OnCalendar=*:0/1
EOL

        systemctl enable unms-update.service &&
        systemctl enable unms-update.timer &&
        systemctl start unms-update.timer

        if [ $? -ne 0 ]; then
          echo >&2 "Failed to enable systemd auto update timer and service"
          exit 1
        fi

      else
        echo >&2 "Failed to enable auto update. UNMS requires either Crontab or systemd timers."
        exit 1
      fi
    fi

  fi

}

delete_old_firmwares() {
  echo "Deleting old firmwares from ${DATA_DIR}/firmwares/unms/*"
  if ! rm -rf "${DATA_DIR}/firmwares/unms"/*; then
    echo >&2 "WARNING: Failed to delete old firmwares"
  fi
}

change_owner() {
  # only necessary when installing for the first time, as root
  if [ "$EUID" -eq 0 ]; then
    cd "${HOME_DIR}"

    if ! chown -R "${USERNAME}" ./*; then
      echo >&2 "Failed to change config files owner"
      exit 1
    fi

    if ! chmod o+x "${APP_DIR}/unms-cli"; then
      echo >&2 "Failed to change permissions on ${APP_DIR}/unms-cli"
      exit 1
    fi

    oldUninstallScript="${APP_DIR}/uninstall.sh"
    if [ -f "${oldUninstallScript}" ]; then
      if rm "${oldUninstallScript}"; then
        echo "Removed ${oldUninstallScript}"
      else
        echo >&2 "Failed to remove ${oldUninstallScript}"
      fi
    fi
  else
    echo "Not running as root - will not change config files owner"
  fi
}

reset_udp_connections() {
  docker run --net=host --privileged --rm ubnt/ucrm-conntrack -D -p udp --dport="${NETFLOW_PORT}" || true
}

start_docker_containers() {
  echo "Starting docker containers."
  cd "${APP_DIR}"
  if ! docker-compose up -d; then
    echo >&2 "Failed to start docker containers"
    exit 1
  fi
}

remove_old_images() {
  echo "Removing old images"
  danglingImages=$(docker images -qf "dangling=true")
  if [ ! -z "${danglingImages}" ]; then docker rmi ${danglingImages} || true; fi

  for imageName in "unms" "unms-nginx" "unms-fluentd" "unms-netflow"; do
    currentImage=$(docker ps --format "{{.Image}}" --filter name="${imageName}"$)
    oldImages=($(docker images "ubnt/${imageName}:"* --format "{{.Repository}}:{{.Tag}}" || true) "")

    if [ ! -z "${currentImage}" ] && [ ! -z "${oldImages}" ]; then
      tmp=()
      for value in "${oldImages[@]}"; do
        [ ! "${value}" = "${currentImage}" ] && tmp+=(${value})
      done
      oldImages=("${tmp[@]:-}")
    fi

    oldImagesString="${oldImages[*]}"
    if [ ! -z "${oldImagesString}" ]; then
      echo "Current ${imageName} image: ${currentImage}"
      echo "Old ${imageName} images: ${oldImagesString}"
      if ! docker rmi ${oldImagesString}; then
        echo "Failed to remove some old images"
      fi
    fi
  done
}

confirm_success() {
  echo "Waiting for UNMS to start"
  n=0
  until [ ${n} -ge 10 ]
  do
    sleep 3s
    unmsRunning=true
    # env -i is to ensure that http[s]_proxy variables are not set
    # Otherwise the check would go through proxy.
    env -i curl -skL "https://127.0.0.1:${HTTPS_PORT}" > /dev/null && break
    echo "."
    unmsRunning=false
    n=$((n+1))
  done

  docker ps

  if [ "${unmsRunning}" = true ]; then
    echo "UNMS is running"
  else
    echo >&2 "UNMS is NOT running"
    exit 1
  fi
}

check_system
check_custom_cert_path
install_docker
install_docker_compose
set_overcommit_memory
create_user
backup_mongo
fix_080_permission_issue # fix issue when migrating from 0.8.0
remove_old_restore_files
migrate_app_files
prepare_templates
determine_public_ports # need to set all docker compose variables
create_data_volumes
create_docker_compose_file # compose file for docker-compose down
login_to_dockerhub
pull_docker_images
build_docker_images
stop_docker_containers
check_free_ports
determine_public_ports # again - now we have all info
create_docker_compose_file # again - compose file for docker-compose up
deploy_templates
save_config
setup_auto_update
delete_old_firmwares
change_owner
reset_udp_connections
start_docker_containers
remove_old_images
confirm_success

exit 0
