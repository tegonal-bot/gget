#!/usr/bin/env bash
#
#    __                          __
#   / /____ ___ ____  ___  ___ _/ /       This script is provided to you by https://github.com/tegonal/gget
#  / __/ -_) _ `/ _ \/ _ \/ _ `/ /        It is licensed under Apache 2.0
#  \__/\__/\_, /\___/_//_/\_,_/_/         Please report bugs and contribute back your improvements
#         /___/
#                                         Version: v0.2.0-SNAPSHOT
#
#######  Description  #############
#
#  internal utility functions
#  no backward compatibility guarantees or whatsoever
#
###################################
set -euo pipefail
shopt -s inherit_errexit

if ! [[ -v dir_of_gget ]]; then
	dir_of_gget="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null && pwd 2>/dev/null)"
	declare -r dir_of_gget
fi

if ! [[ -v dir_of_tegonal_scripts ]]; then
	dir_of_tegonal_scripts="$dir_of_gget/../lib/tegonal-scripts/src"
	source "$dir_of_tegonal_scripts/setup.sh" "$dir_of_tegonal_scripts"
fi

function deleteDirChmod777() {
	local -r dir=$1
	# e.g files in .git will be write-protected and we don't want sudo for this command
	chmod -R 777 "$dir"
	rm -r "$dir"
}

function errorNoGpgKeysImported() {
	local -r remote=$1
	local -r publicKeysDir=$2
	local -r gpgDir=$3
	local -r unsecurePattern=$4

	logError "no GPG keys imported, you won't be able to pull files from the remote \033[0;36m%s\033[0m without using %s true\n" "$remote" "$unsecurePattern"
	printf >&2 "Alternatively, you can:\n- place public keys in %s or\n- setup a gpg store yourself at %s\n" "$publicKeysDir" "$gpgDir"
	deleteDirChmod777 "$gpgDir"
	return 1
}

function findAscInDir() {
	local -r dir=$1
	shift
	find "$dir" -maxdepth 1 -type f -name "*.asc" "$@"
}

function noAscInDir() {
	local -r dir=$1
	shift 1
	local numberOfAsc
	# we are aware of that set -e is disabled for findAscInDir
	#shellcheck disable=SC2310
	numberOfAsc=$(findAscInDir "$dir" | wc -l) || die "could not find the number of *.asc files in dir %s, see errors above" "$dir"
	((numberOfAsc == 0))
}

function checkWorkingDirExists() {
	local workingDir=$1
	shift

	local workingDirPattern
	source "$dir_of_gget/shared-patterns.source.sh"

	if ! [[ -d $workingDir ]]; then
		logError "working directory \033[0;36m%s\033[0m does not exist" "$workingDir"
		echo >&2 "Check for typos and/or use $workingDirPattern to specify another"
		return 9
	fi
}

function checkRemoteDirExists() {
	local -r workingDirAbsolute=$1
	local -r remote=$2
	shift 2
	local remoteDir
	source "$dir_of_gget/paths.source.sh"

	if ! [[ -d $remoteDir ]]; then
		logError "remote \033[0;36m%s\033[0m does not exist, check for typos.\nFollowing the remotes which exist:" "$remote"
		sourceOnce "$dir_of_gget/gget-remote.sh"
		gget_remote_list -w "$workingDirAbsolute"
		return 9
	else
		return 0
	fi
}

function invertBool() {
	local b=$1
	if [[ $b == true ]]; then
		echo "false"
	else
		echo "true"
	fi
}

function gitDiffChars() {
	local hash1 hash2
	hash1=$(git hash-object -w --stdin <<<"$1")
	hash2=$(git hash-object -w --stdin <<<"$2")
	shift 2
	git --no-pager diff "$hash1" "$hash2" \
		--word-diff=color --word-diff-regex . --ws-error-highlight=all |
		grep -A 1 @@ | tail -n +2
}
