#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PATH="${PATH}:/usr/local/bin"

# prerrequisites "command|package"
PREREQUISITES=(
  "curl|curl"
  "sed|sed"
  "envsubst|gettext-base"
)

COMPOSE_PROJECT_NAME="unms"
USERNAME="${UNMS_USER:-unms}"
if getent passwd "${USERNAME}" >/dev/null; then
  HOME_DIR="$(getent passwd "${USERNAME}" | cut -d: -f6)"
else
  HOME_DIR="${UNMS_HOME_DIR:-"/home/${USERNAME}"}"
fi

# files and directoris
export APP_DIR="${HOME_DIR}/app"
export DATA_DIR="${HOME_DIR}/data"
export RESTORE_DIR="${DATA_DIR}/unms-backups/restore"
export CONFIG_DIR="${APP_DIR}/conf"
export CONFIG_FILE="${APP_DIR}/unms.conf"
export METADATA_FILE="${APP_DIR}/metadata"
export DOCKER_COMPOSE_INSTALL_PATH="/usr/local/bin"
export DOCKER_COMPOSE_FILENAME="docker-compose.yml"
export DOCKER_COMPOSE_PATH="${APP_DIR}/${DOCKER_COMPOSE_FILENAME}"
export DOCKER_COMPOSE_TEMPLATE_FILENAME="docker-compose.yml.template"
export DOCKER_COMPOSE_TEMPLATE_PATH="${APP_DIR}/${DOCKER_COMPOSE_TEMPLATE_FILENAME}"

if [ "${SCRIPT_DIR}" = "${APP_DIR}" ]; then
  echo >&2 "Please don't run the installation script in the application directory ${APP_DIR}"
  exit 1
fi

# UNMS variables
export UNMS_HTTP_PORT="8081"
export UNMS_WS_PORT="8082"
export UNMS_WS_SHELL_PORT="8083"
export UNMS_WS_API_PORT="8084"
export UNMS_POSTGRES_USER="unms"
export UNMS_POSTGRES_DB="unms"
export UNMS_POSTGRES_SCHEMA="unms"
export UNMS_POSTGRES_PASSWORD="$(LC_CTYPE=C tr -dc "a-zA-Z0-9" < /dev/urandom | fold -w 48 | head -n 1 || true)"
export UNMS_TOKEN="$(LC_CTYPE=C tr -dc "a-zA-Z0-9" < /dev/urandom | fold -w 48 | head -n 1 || true)"
export UNMS_DEPLOYMENT=""
export UNMS_VERSION="$(grep "^version=" "${SCRIPT_DIR}/metadata" | sed 's/version=//')"
export UNMS_IP_WHITELIST=""
export ALTERNATIVE_HTTP_PORT="8080"
export ALTERNATIVE_HTTPS_PORT="8443"
export ALTERNATIVE_SUSPEND_PORT="8081"
export ALTERNATIVE_NETFLOW_PORT="2056"
export SECURE_LINK_SECRET="$(LC_CTYPE=C tr -dc "a-zA-Z0-9" < /dev/urandom | fold -w 100 | head -n 1 || true)"

# UCRM variables
export UCRM_ENABLED="true"
export UCRM_CONFIGURABLE="true"
export UCRM_DOCKER_IMAGE="ubnt/unms-crm"
export UCRM_VERSION="3.0.0-beta.4"
export UCRM_POSTGRES_PASSWORD="$(LC_CTYPE=C tr -dc "a-zA-Z0-9" < /dev/urandom | fold -w 48 | head -n 1 || true)"
export UCRM_SECRET="$(LC_CTYPE=C tr -dc "a-zA-Z0-9" < /dev/urandom | fold -w 48 | head -n 1 || true)"
export UCRM_USER="${USERNAME}"
export UCRM_POSTGRES_USER="ucrm"
export UCRM_POSTGRES_DB="unms"
export UCRM_POSTGRES_SCHEMA="ucrm"
export UCRM_MAILER_ADDRESS="127.1.0.1"
export UCRM_MAILER_USERNAME="username"
export UCRM_MAILER_PASSWORD="password"
export NODE_ENV="production"

# other variables
export HTTP_PORT="80"
export HTTPS_PORT="443"
export SUSPEND_PORT="81"
export WS_PORT=""
export PROXY_HTTPS_PORT=""
export PROXY_WS_PORT=""
export NETFLOW_PORT="2055"
export VERSION="latest"
export DEMO="false"
export USE_LOCAL_IMAGES="false"
export DOCKER_IMAGE="ubnt/unms"
export DOCKER_REGISTRY="docker.io"
export DOCKER_USERNAME=""
export DOCKER_PASSWORD=""
export SSL_CERT_DIR=""
export SSL_CERT=""
export SSL_CERT_KEY=""
export SSL_CERT_CA=""
export HOST_TAG=""
export UNATTENDED="false"
export UPDATING="false"
export NO_AUTO_UPDATE="false"
export NO_OVERCOMMIT_MEMORY="false"
export BRANCH="master"
export SUBNET=""
export CLUSTER_SIZE="auto"
export IPAM_PUBLIC=""
export IPAM_PRIVATE=""
export CERT_DIR_MAPPING_NGINX=""
export USERCERT_DIR_MAPPING_NGINX=""
export POSTGRES_USER="postgres"
export POSTGRES_PASSWORD="$(LC_CTYPE=C tr -dc "a-zA-Z0-9" < /dev/urandom | fold -w 48 | head -n 1 || true)"
export CURRENT_VERSION="$(cat "${METADATA_FILE}" 2>/dev/null | grep '^version=' | sed 's/version=//'|| true)"
export DELETE_CRM_DATA="false"
export ENV_DIR=
export ENV_FILES_UNMS=
export ENV_FILES_UCRM=

fail() {
  echo -e "ERROR: $1" >&2
  exit 1
}

read_previous_config() {
  # read WS port settings from existing running container
  # they were not saved to config file in versions <=0.7.18
  if ! oldEnv="$(docker inspect --format '{{ .Config.Env }}' unms)"; then
    echo "Couldn't read WS port config from existing UNMS container"
  else
    WS_PORT="$(docker ps --filter "name=unms$" --filter "status=running" --format "{{.Ports}}" | sed -E "s/.*0.0.0.0:([0-9]+)->8444.*|.*/\1/")"
    echo "Setting WS_PORT=${WS_PORT}"
    PROXY_WS_PORT="$(echo "${oldEnv}" | sed -E "s/.*[ []PUBLIC_WS_PORT=([0-9]*).*|.*/\1/")"
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
  UCRM_POSTGRES_DB="${UNMS_POSTGRES_DB}"
}

# parse arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --demo)
      echo "Setting DEMO=true"
      DEMO="true"
      ;;
    --update)
      echo "Restoring previous configuration"
      read_previous_config
      UPDATING="true"
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
    --enable-ucrm)
      echo "Setting UCRM_ENABLED=true"
      UCRM_ENABLED="true"
      ;;
    --ucrm-configurable)
      echo "Setting UCRM_CONFIGURABLE=true"
      UCRM_CONFIGURABLE="true"
      ;;
    --ucrm-version)
      echo "Setting UCRM_VERSION=$2"
      UCRM_VERSION="$2"
      ;;
    --ucrm-docker-image)
      echo "Setting UCRM_DOCKER_IMAGE=$2"
      UCRM_DOCKER_IMAGE="$2"
      shift # past argument value
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
    --docker-registry)
      echo "Setting DOCKER_REGISTRY=$2"
      DOCKER_REGISTRY="$2"
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
    --suspend-port)
      echo "Setting SUSPEND_PORT=$2"
      SUSPEND_PORT="$2"
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
      shift # past argument value
      ;;
    --deployment)
      echo "Setting UNMS_DEPLOYMENT=$2"
      UNMS_DEPLOYMENT=$2
      shift # past argument value
      ;;
    --ip-whitelist)
      echo "Setting UNMS_IP_WHITELIST=$2"
      UNMS_IP_WHITELIST=$2
      shift # past argument value
      ;;
    --env-dir)
      echo "Setting ENV_DIR=$2"
      ENV_DIR=$2
      shift # past argument value
      ;;
    *)
      # unknown option
      ;;
  esac
  shift # past argument key
done

# '+' symbol is not allowed in docker tags, replace with '-'
export DOCKER_TAG=${VERSION//+/-}
export UCRM_DOCKER_TAG=${UCRM_VERSION//+/-}

# check that none or all three SSL variables are set
if [ ! -z "${SSL_CERT_DIR}" ] || [ ! -z "${SSL_CERT}" ] || [ ! -z "${SSL_CERT_KEY}" ]; then
  if [ -z "${SSL_CERT_DIR}" ]; then echo >&2 "Please set --ssl-cert-dir"; exit 1; fi
  if [ -z "${SSL_CERT}" ]; then echo >&2 "Please set --ssl-cert"; exit 1; fi
  if [ -z "${SSL_CERT_KEY}" ]; then echo >&2 "Please set --ssl-cert-key"; exit 1; fi
fi

# check subnet and prepare the networks section of docker compose file
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

if [ ! -z "${ENV_DIR}" ]; then
  # prepare env_file sections of the docker compose file
  [ -f ${ENV_DIR}/unms.env ] && ENV_FILES_UNMS=$(printf "env_file:\n      - ${ENV_DIR}/unms.env")
  [ -f ${ENV_DIR}/ucrm.env ] && ENV_FILES_UCRM=$(printf "env_file:\n      - ${ENV_DIR}/ucrm.env")
fi

# prepare --silent option for curl
curlSilent=""
if [ "${UNATTENDED}" = "true" ]; then
  curlSilent="--silent"
fi

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

version_older() {
  ! version_equal_or_newer "$1" "$2"
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

check_update_allowed() {
  if [ -z "${CURRENT_VERSION}" ]; then
    return 0
  fi

  if echo "${CURRENT_VERSION}" | grep -q '^1.0.0-dev' && echo "${VERSION}" | grep -vq '^1.0.0-dev'; then
    if [ "$UNATTENDED" = true ]; then
      fail "Unattended update from version 1.0.0-dev to a non-dev version is not allowed."
    fi

    echo "Updating from CRM testing version. All CRM data will be deleted."
    confirm "Would you like to continue with the installation?" || exit 1
    export DELETE_CRM_DATA="true"
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

check_free_space() {
  dockerRootDir="$(docker info --format='{{ print .DockerRootDir }}')"
  freeSpace="$(df -m "${dockerRootDir}" | tail -1 | awk '{print $4}')"
  local minRequiredSpace=3000 # MB
  if [ "${USE_LOCAL_IMAGES}" = "true" ]; then
    minRequiredSpace=500 # MB
  fi
  if [[ "${freeSpace}" -lt "${minRequiredSpace}" ]]; then
    echo >&2 "There is not enough disk space available to safely install UNMS. At least ${minRequiredSpace} MB is required."
    echo >&2 "You have ${freeSpace} MB of available disk space in ${dockerRootDir}"
    echo >&2 -e "\n----------------\n"
    echo >&2 "We recommend running \"docker system prune\" once in a while to clean unused containers, images, etc."
    echo >&2 "You can determine how much space can be cleaned up by running \"docker system df\""

    exit 1
  fi
}

install_docker() {
  if ! which docker > /dev/null 2>&1; then
    echo "Download and install Docker"
    (
      unset VERSION # we use this for UNMS version, docker thinks it is the docker version
      export CHANNEL="nightly"
      curl -fsSL https://get.docker.com/ | sh
    )

    systemctl enable docker
    systemctl start docker
  fi

  DOCKER_VERSION=$(docker -v | sed 's/.*version \([0-9.]*\).*/\1/');
  echo "Docker version: ${DOCKER_VERSION}"
  if ! version_equal_or_newer "${DOCKER_VERSION}" "1.13.1" ; then
    echo "Docker version ${DOCKER_VERSION} is not supported. Please upgrade to version 1.13.1 or newer."
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
  elif realpath "$(which docker-compose)" | grep snap > /dev/null 2>&1; then
    fail "It appears that docker-compose was installed using snap package manager. UNMS does not work with this version of docker-compose. Please uninstall docker-compose and then re-run the installation script."
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
    if [ -z "$(getent group ${USERNAME})" ]; then
      useradd -m -d "${HOME_DIR}" -G docker "${USERNAME}" || fail "Failed to create user '${USERNAME}'"
    else
      useradd -m -d "${HOME_DIR}" -g "${USERNAME}" -G docker "${USERNAME}" || fail "Failed to create user '${USERNAME}'"
    fi
  elif ! getent group docker | grep -q "\b${USERNAME}\b" \
      || ! [ -d "${HOME_DIR}" ] \
      || [ "$(stat --format '%u' "${HOME_DIR}")" != "$(id -u "${USERNAME}")" ]; then
    echo >&2 "WARNING: User '${USERNAME}' already exists. We are going to ensure that the"
    echo >&2 "user is in the 'docker' group and that its home '${HOME_DIR}' dir exists and"
    echo >&2 "is owned by the user."
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

  if [ "$(stat --format '%u' "${HOME_DIR}")" != "$(id -u "${USERNAME}")" ]; then
    chown "${USERNAME}" "${HOME_DIR}"
  fi

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

start_postgres() {
  echo "Starting postgres DB."
  docker-compose -p unms -f "${DOCKER_COMPOSE_PATH}" up --no-deps -d postgres >/dev/null || fail "Failed to start Postgres DB."
  for delay in 1 2 2 5 10 10 0; do
    test "${delay}" != "0" || fail "Postgres DB failed to start in time."
    if docker-compose -p unms -f "${DOCKER_COMPOSE_PATH}" exec -T postgres pg_isready 2>&1 >/dev/null; then
      break
    fi
    sleep "${delay}"
  done
}

stop_postgres() {
  docker-compose -p unms -f "${DOCKER_COMPOSE_PATH}" down || fail "Failed to stop Postgres DB."
}

exec_pg_dump() {
  docker-compose -p unms -f "${DOCKER_COMPOSE_PATH}" exec -T postgres pg_dump --username postgres --no-password "$@"
}

exec_psql() {
  docker-compose -p unms -f "${DOCKER_COMPOSE_PATH}" exec -T postgres psql --username postgres --no-password --no-align --tuples-only --quiet --dbname "${UNMS_POSTGRES_DB}" "$@"
}

exec_psql_command() {
  exec_psql --command "${1}"
}

fix_postgres() {
  test -d "${DATA_DIR}/postgres" || return 0 # do nothing during first installation

  local isReinstall="$( [ "${UPDATING}" = "false" ] && echo "true" || echo "false")"
  local isPreUcrmVersion="$( ( [ -z "${CURRENT_VERSION}" ] \
    || version_older "${CURRENT_VERSION}" "0.13.99") > /dev/null && echo "true" || echo "false")"
  local isEarlyUcrmVersion="$( ( [ -z "${CURRENT_VERSION}" ] \
    || echo "${CURRENT_VERSION}" | grep --quiet '^0.14.0-dev.1' \
    || echo "${CURRENT_VERSION}" | grep --quiet '^0.14.0-alpha.1' \
    || echo "${CURRENT_VERSION}" | grep --quiet '^1.0.0-dev') > /dev/null && echo "true" || echo "false")"

  if [ "${isReinstall}" = "false" ] \
    && [ "${isPreUcrmVersion}" = "false" ] \
    && [ "${isEarlyUcrmVersion}" = "false" ];
  then
    echo "No need to fix postgres."
    return 0
  fi

  start_postgres

  if [ "${isPreUcrmVersion}" = "true" ]; then
    # Previous versions of UNMS used 'postgres' user without password. New versions will use 'unms' user with password
    # and the 'postgres' user will be password protected.
    # Update passwords.
    echo "Setting password for Postgres DB."
    exec_psql_command "ALTER USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}'" > /dev/null || fail "Failed to set password for user '${POSTGRES_USER}'."
    echo "Creating DB user ${UNMS_POSTGRES_USER}."
    exec_psql_command "CREATE USER ${UNMS_POSTGRES_USER} SUPERUSER PASSWORD '${UNMS_POSTGRES_PASSWORD}'" > /dev/null || fail "Failed to create DB user '${UNMS_POSTGRES_USER}'."
    exec_psql_command "GRANT ALL PRIVILEGES ON DATABASE ${UNMS_POSTGRES_DB} TO ${UNMS_POSTGRES_USER}" > /dev/null  || fail "Failed to grant privileges on DB '${UNMS_POSTGRES_DB}' to user '${UNMS_POSTGRES_USER}'."
    echo "Creating DB user ${UCRM_POSTGRES_USER}."
    exec_psql_command "CREATE USER ${UCRM_POSTGRES_USER} SUPERUSER PASSWORD '${UCRM_POSTGRES_PASSWORD}'" > /dev/null || fail "Failed to create DB user '${UCRM_POSTGRES_USER}'."
    exec_psql_command "GRANT ALL PRIVILEGES ON DATABASE ${UCRM_POSTGRES_DB} TO ${UCRM_POSTGRES_USER}" > /dev/null  || fail "Failed to grant privileges on DB '${UCRM_POSTGRES_DB}' to user '${UCRM_POSTGRES_USER}'."
    # Disallow remote connections without password.
    echo "Disallowing Postgres DB connection without password."
    docker-compose -p unms -f "${DOCKER_COMPOSE_PATH}" exec -T postgres \
      sed -i -- 's/host[[:space:]]*all[[:space:]]*all[[:space:]]*all[[:space:]]*trust/host all all all md5/' "/var/lib/postgresql/data/pgdata/pg_hba.conf" || fail "Failed to restrict access to Postgres DB."
  elif [ "${isReinstall}" = "true" ]; then
    # Doing reinstall without --update flag. New passwords have been generated, apply them to the DB.
    echo "Updating Postgres DB passwords."
    exec_psql_command "ALTER USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}'" > /dev/null || fail "Failed to update password for user '${POSTGRES_USER}'."
    exec_psql_command "ALTER USER ${UNMS_POSTGRES_USER} WITH PASSWORD '${UNMS_POSTGRES_PASSWORD}'" > /dev/null || fail "Failed to update password for user '${UNMS_POSTGRES_USER}'."
    exec_psql_command "ALTER USER ${UCRM_POSTGRES_USER} WITH PASSWORD '${UCRM_POSTGRES_PASSWORD}'" > /dev/null || fail "Failed to update password for user '${UCRM_POSTGRES_PASSWORD}'."
    echo "Disallowing Postgres DB connection without password."
    docker-compose -p unms -f "${DOCKER_COMPOSE_PATH}" exec -T postgres \
      sed -i -- 's/host[[:space:]]*all[[:space:]]*all[[:space:]]*all[[:space:]]*trust/host all all all md5/' "/var/lib/postgresql/data/pgdata/pg_hba.conf" || true
  fi

  if [ "${isPreUcrmVersion}" = "true" ] || [ "${isEarlyUcrmVersion}" = "true" ]; then
    # Move unms tables from public schema to unms schema
    echo "Checking exitence of unms schema."
    if ! exec_psql_command "\dn" | cut -d \| -f 1 | grep -qw unms; then
      echo "Changing Postgres DB schemas."
      exec_psql_command "ALTER SCHEMA public RENAME TO ${UNMS_POSTGRES_SCHEMA}" > /dev/null || fail "Failed to rename public schema to '${UNMS_POSTGRES_SCHEMA}'."
      exec_psql_command "CREATE SCHEMA IF NOT EXISTS public" > /dev/null || fail "Failed to create DB schema 'public'."
      exec_psql_command "CREATE SCHEMA IF NOT EXISTS ${UCRM_POSTGRES_SCHEMA}" > /dev/null || fail "Failed to create DB schema '${UCRM_POSTGRES_SCHEMA}'."
      exec_psql_command "ALTER USER ${UNMS_POSTGRES_USER} SET search_path = ${UNMS_POSTGRES_SCHEMA},public" > /dev/null  || fail "Failed to set search path for DB user '${UNMS_POSTGRES_USER},public'."
      exec_psql_command "ALTER USER ${UCRM_POSTGRES_USER} SET search_path = ${UCRM_POSTGRES_SCHEMA},public" > /dev/null  || fail "Failed to set search path for DB user '${UCRM_POSTGRES_USER},public'."
      exec_psql_command "ALTER SCHEMA ${UNMS_POSTGRES_SCHEMA} OWNER TO ${UNMS_POSTGRES_USER}" > /dev/null || fail "Failed to set ownership of schema '${UNMS_POSTGRES_SCHEMA}' to user '${UNMS_POSTGRES_USER}'."
      exec_psql_command "ALTER SCHEMA ${UCRM_POSTGRES_SCHEMA} OWNER TO ${UCRM_POSTGRES_USER}" > /dev/null || fail "Failed to set ownership of schema '${UCRM_POSTGRES_SCHEMA}' to user '${UCRM_POSTGRES_USER}'."
      extensions="$(exec_psql_command "SELECT extname FROM pg_extension WHERE extname != 'plpgsql'")"
      for extension in ${extensions}; do
        exec_psql_command "ALTER EXTENSION \"${extension}\" SET SCHEMA public" || fail "Failed to move extension '${extension}' to schema 'public'."
      done
    else
      echo "Schemas are already changed."
    fi
  fi

  if [ "${isEarlyUcrmVersion}" = "true" ]; then
    # Early versions 0.14.0 and 1.0.0-dev contained separate UCRM database.
    echo "Checking separate ucrm database."
    if exec_psql -lqt | cut -d \| -f 1 | grep --quiet "^ucrm[[:space:]]*$"; then
      echo "Migrating UCRM database."
      # ucrm database exists, migrate its content to ucrm namespace in the unms database
      exec_psql_command "DROP SCHEMA ${UCRM_POSTGRES_SCHEMA} CASCADE" || fail "Failed to drop DB schema '${UCRM_POSTGRES_SCHEMA}'."
      exec_pg_dump ucrm > "${DATA_DIR}/postgres/ucrm.sql" || fail "Failed to dump 'ucrm' database."
      exec_psql -f "/var/lib/postgresql/data/pgdata/ucrm.sql" > /dev/null || fail "Failed to restore 'ucrm' database."
      rm "${DATA_DIR}/postgres/ucrm.sql"
      exec_psql_command "ALTER SCHEMA public RENAME TO ${UCRM_POSTGRES_SCHEMA}" || echo "Failed to rename public schema to '${UCRM_POSTGRES_SCHEMA}'."
      exec_psql_command "ALTER SCHEMA ${UCRM_POSTGRES_SCHEMA} OWNER TO ${UCRM_POSTGRES_USER}" > /dev/null || fail "Failed to set ownership of schema '${UCRM_POSTGRES_SCHEMA}' to user '${UCRM_POSTGRES_USER}'."
      exec_psql_command "CREATE SCHEMA IF NOT EXISTS public" > /dev/null || fail "Failed to create DB schema 'public'."
      extensions="$(exec_psql_command "SELECT extname FROM pg_extension WHERE extname != 'plpgsql'")"
      for extension in ${extensions}; do
        exec_psql_command "ALTER EXTENSION \"${extension}\" SET SCHEMA public" > /dev/null || fail "Failed to move extension '${extension}' to schema 'public'."
      done
      exec_psql_command "DROP database ucrm" > /dev/null || fail "Failed to drop database 'ucrm'."
    else
      echo "The 'ucrm' database has already been migrated."
    fi
  fi

  stop_postgres
}

remove_crm_testing_data() {
  if [ "${DELETE_CRM_DATA}" != "true" ]; then
    return 0;
  fi

  start_postgres

  echo "Dropping DB 'ucrm'."
  exec_psql_command "DROP DATABASE ucrm" > /dev/null || echo "Failed to drop DB 'ucrm'."
  echo "Dropping schema 'ucrm'."
  exec_psql_command "DROP SCHEMA ucrm CASCADE" > /dev/null || echo "Failed to drop DB schema 'ucrm'."
  echo "Creating DB schema '${UCRM_POSTGRES_SCHEMA}'."
  exec_psql_command "CREATE SCHEMA IF NOT EXISTS ${UCRM_POSTGRES_SCHEMA} AUTHORIZATION ${UCRM_POSTGRES_USER}" > /dev/null || fail "Failed to create DB schema '${UCRM_POSTGRES_SCHEMA}'."

  stop_postgres

  local ucrmDir="${DATA_DIR}/ucrm"
  echo "Removing UCRM directory '${ucrmDir}'"
  rm -rf "${ucrmDir}" || fail "Failed to clear ucrm directory '${ucrmDir}'."
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
  if [ -f "${oldDockerComposeFile}" ]; then mv -u "${oldDockerComposeFile}" "${DOCKER_COMPOSE_PATH}"; fi
  if [ -f "${oldDockerComposeTemplate}" ]; then mv -u "${oldDockerComposeTemplate}" "${DOCKER_COMPOSE_TEMPLATE_PATH}"; fi
  if [ -d "${oldConfigDir}" ]; then rm -rf "${oldConfigDir}"; fi

  chown -R "${USERNAME}" "${APP_DIR}" || true
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
  envsubst < "${SCRIPT_DIR}/${DOCKER_COMPOSE_TEMPLATE_FILENAME}" > "${SCRIPT_DIR}/${DOCKER_COMPOSE_FILENAME}" || fail "Failed to create docker-compose.yml"
}

login_to_dockerhub() {
  if [[ ${DOCKER_USERNAME} ]]; then
    echo "Logging in to Docker Hub as ${DOCKER_USERNAME}"
    docker login -u="${DOCKER_USERNAME}" -p="${DOCKER_PASSWORD}" "${DOCKER_REGISTRY}"
  fi
}

pull_docker_images() {
  if [ "${USE_LOCAL_IMAGES}" = "true" ]; then
    echo "Will try to use local Docker images."
    return 0
  fi

  echo "Pulling docker images."
  local newDockerComposeFile="${SCRIPT_DIR}/${DOCKER_COMPOSE_FILENAME}"
  if [ -f "${newDockerComposeFile}" ]; then
    docker-compose -p unms -f "${newDockerComposeFile}" pull || fail "Failed to pull docker images"
  fi

  docker pull ubnt/ucrm-conntrack || fail "Failed to pull ubnt/ucrm-conntrack image"
}

stop_docker_containers() {
  if [ -f "${DOCKER_COMPOSE_PATH}" ] && [ -n "$(docker-compose -p unms -f "${DOCKER_COMPOSE_PATH}" ps -q)" ]; then
    echo "Stopping docker containers."
    docker-compose -p unms -f "${DOCKER_COMPOSE_PATH}" down && RC=$? || RC=$?
    if [ "${RC}" -gt 0 ]; then
      # Failed to stop UNMS. Try to restart it before exitting.
      "${APP_DIR}/unms-cli" start || true
      fail "Failed to stop docker containers. This usually happens due to problem in docker service. Try restarting docker
service with 'sudo systemctl restart docker' and then retry the installation."
    fi
  fi
}

check_raw_sockets() {
  # Try to create ping session. If it fails the docker is running without 'setcap cap_net_raw' support.
  docker run --rm --entrypoint /usr/sbin/setcap "${DOCKER_IMAGE}:${DOCKER_TAG}" \
    cap_net_raw=pe /usr/local/bin/node 2>/dev/null \
    || fail "This Docker installation does not support setting file capabilities using 'setcap' command.
This happens usually due to lack of support from Docker's storage driver.
Please check the storage driver used by Docker by running 'docker info | grep \"Storage Driver\"'. It should be
set to overlay2 or similar filesystem with support for extended file attributes.
To change Docker's storage driver to overlay2 first check that the kernel supports it by running \"modprobe -a overlay\".
If overlay2 is supported edit /etc/docker/daemon.json and add { \"storage-driver\": \"overlay2\" }.
Restart Docker service with 'sudo systemctl restart docker' and run this installation script again."
  echo "File capabilities are supported."
}

try_to_bind_port() {
  local port="${1}"
  local protocol="${2}" # tcp or udp
  # Try to create docker container that bounds given port.
  docker run --rm -p "${port}:${port}/${protocol}" --entrypoint /bin/echo "${DOCKER_IMAGE}:${DOCKER_TAG}" "Port ${port}/${protocol} is free." 2>/dev/null
}

check_free_ports() {
  echo "Checking available ports"
  while ! try_to_bind_port "${HTTP_PORT}" "tcp"; do
    test "${UNATTENDED}" = "false" || fail "Port ${HTTP_PORT} is in use."
    read -r -p "Port ${HTTP_PORT} is already in use, please choose a different HTTP port for UNMS. [${ALTERNATIVE_HTTP_PORT}]: " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-$ALTERNATIVE_HTTP_PORT}
  done

  while ! try_to_bind_port "${HTTPS_PORT}" "tcp"; do
    test "${UNATTENDED}" = "false" || fail "Port ${HTTPS_PORT} is in use."
    read -r -p "Port ${HTTPS_PORT} is already in use, please choose a different HTTPS port for UNMS. [${ALTERNATIVE_HTTPS_PORT}]: " HTTPS_PORT
    HTTPS_PORT=${HTTPS_PORT:-$ALTERNATIVE_HTTPS_PORT}
  done

  while ! try_to_bind_port "${SUSPEND_PORT}" "tcp"; do
    if [ "${UNATTENDED}" = true ]; then
      echo >&2 "WARNING: Port ${SUSPEND_PORT} is in use. Selecting ${ALTERNATIVE_SUSPEND_PORT} port for suspension."
      SUSPEND_PORT="${ALTERNATIVE_SUSPEND_PORT}"
      break
    else
      read -r -p "Port ${SUSPEND_PORT} is already in use, please choose a different Suspension port for UNMS. [${ALTERNATIVE_SUSPEND_PORT}]: " SUSPEND_PORT
      SUSPEND_PORT=${SUSPEND_PORT:-$ALTERNATIVE_SUSPEND_PORT}
    fi
  done

  while ! try_to_bind_port "${NETFLOW_PORT}" "udp"; do
    if [ "${UNATTENDED}" = true ]; then
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
  CERT_DIR_MAPPING_NGINX="- ${DATA_DIR}/cert:/cert"
  if [ -z "${SSL_CERT_DIR}" ]; then
    USERCERT_DIR_MAPPING_NGINX=""
  else
    echo "Will mount ${SSL_CERT_DIR} as /usercert"
    USERCERT_DIR_MAPPING_NGINX="- ${SSL_CERT_DIR}:/usercert:ro"
  fi

  # Redis, Postgres, Fluentd
  mkdir -p -m u+rwX,g-rwx,o-rwx "${DATA_DIR}/redis"
}

deploy_templates() {
  echo "Deploying templates"
  mkdir -p "${APP_DIR}"
  cp -r "${SCRIPT_DIR}"/* "${APP_DIR}/" || fail "Failed to deploy templates to ${APP_DIR}"
}

save_config() {
  echo "Writing config file"
  if ! cat >"${CONFIG_FILE}" <<EOL
VERSION="${VERSION}"
DEMO="${DEMO}"
NODE_ENV="${NODE_ENV}"
DOCKER_IMAGE="${DOCKER_IMAGE}"
UCRM_DOCKER_IMAGE="${UCRM_DOCKER_IMAGE}"
DATA_DIR="${DATA_DIR}"
HTTP_PORT="${HTTP_PORT}"
HTTPS_PORT="${HTTPS_PORT}"
SUSPEND_PORT="${SUSPEND_PORT}"
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
UCRM_ENABLED="${UCRM_ENABLED}"
UNMS_POSTGRES_USER="${UNMS_POSTGRES_USER}"
UNMS_POSTGRES_DB="${UNMS_POSTGRES_DB}"
UNMS_POSTGRES_SCHEMA="${UNMS_POSTGRES_SCHEMA}"
UNMS_POSTGRES_PASSWORD="${UNMS_POSTGRES_PASSWORD}"
UNMS_TOKEN="${UNMS_TOKEN}"
UNMS_DEPLOYMENT="${UNMS_DEPLOYMENT}"
UNMS_IP_WHITELIST="${UNMS_IP_WHITELIST}"
UCRM_POSTGRES_USER="${UCRM_POSTGRES_USER}"
UCRM_POSTGRES_DB="${UCRM_POSTGRES_DB}"
UCRM_POSTGRES_SCHEMA="${UCRM_POSTGRES_SCHEMA}"
UCRM_POSTGRES_PASSWORD="${UCRM_POSTGRES_PASSWORD}"
UCRM_SECRET="${UCRM_SECRET}"
POSTGRES_USER="${POSTGRES_USER}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
EOL
  then
    fail "Failed to save config file ${CONFIG_FILE}"
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
  if [ "${EUID}" -eq 0 ]; then
    cd "${HOME_DIR}"

    if ! chown -R "${USERNAME}" ./*; then
      echo >&2 "Failed to change config files owner"
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

  if ! chmod +x "${APP_DIR}/unms-cli"; then
    echo >&2 "Failed to change permissions on ${APP_DIR}/unms-cli"
    exit 1
  fi
}

reset_udp_connections() {
  docker run --net=host --privileged --rm ubnt/ucrm-conntrack -D -p udp --dport="${NETFLOW_PORT}" || true
}

start_docker_containers() {
  echo "Starting docker containers."
  "${APP_DIR}/unms-cli" start || fail "Failed to start docker containers"
}

remove_old_images() {
  echo "Removing old images"
  danglingImages=$(docker images -qf "dangling=true")
  if [ ! -z "${danglingImages}" ]; then docker rmi ${danglingImages} || true; fi

  for imageName in "unms" "ucrm" "unms-crm" "unms-nginx" "unms-fluentd" "unms-netflow"; do
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
    fail "UNMS is NOT running"
  fi
}

check_system
check_update_allowed
check_custom_cert_path
install_docker
install_docker_compose
check_free_space
set_overcommit_memory
create_user
backup_mongo
fix_080_permission_issue # fix issue when migrating from 0.8.0
remove_old_restore_files
migrate_app_files
determine_public_ports # need to set all docker compose variables
create_data_volumes
create_docker_compose_file # compose file for docker-compose down
login_to_dockerhub
pull_docker_images
stop_docker_containers
check_raw_sockets
check_free_ports
determine_public_ports # again - now we have all info
create_docker_compose_file # again - compose file for docker-compose up
deploy_templates
remove_crm_testing_data
fix_postgres
save_config
setup_auto_update
delete_old_firmwares
change_owner
reset_udp_connections
start_docker_containers
remove_old_images
confirm_success

exit 0
