#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail

temp="/tmp/unms-install"

args="$*"
version=""
branch="master"

branchRegex=" --branch ([^ ]+)"
if [[ " ${args}" =~ ${branchRegex} ]]; then
  branch="${BASH_REMATCH[1]}"
fi
echo "branch=${branch}"

repo="https://raw.githubusercontent.com/Ubiquiti-App/UNMS/${branch}"

versionRegex=" --version ([^ ]+)"
if [[ " ${args}" =~ ${versionRegex} ]]; then
  version="${BASH_REMATCH[1]}"
fi

if [ -z "${version}" ]; then
  latestVersionUrl="${repo}/latest-version"
  if ! version=$(curl -fsS "${latestVersionUrl}"); then
    echo >&2 "Failed to obtain latest version info from ${latestVersionUrl}"
    exit 1
  fi
fi
echo version="${version}"

rm -rf "${temp}"
if ! mkdir "${temp}"; then
  echo >&2 "Failed to create temporary directory"
  exit 1
fi

cd "${temp}"
packageVersion="${version%%+*}" # package name never includes build number
echo "Downloading installation package for version ${packageVersion}."
packageUrl="${repo}/unms-${packageVersion}.tar.gz"
if ! curl -sS "${packageUrl}" | tar xz; then
  echo >&2 "Failed to download installation package ${packageUrl}"
  exit 1
fi

chmod +x install-full.sh
./install-full.sh ${args} --version "${version}"

cd ~
if ! rm -rf "${temp}"; then
  echo >&2 "Warning: Failed to remove temporary directory ${temp}"
fi
