#!/usr/bin/env bash
#
#    __                          __
#   / /____ ___ ____  ___  ___ _/ /       This script is provided to you by https://github.com/tegonal/gget
#  / __/ -_) _ `/ _ \/ _ \/ _ `/ /        It is licensed under Apache 2.0
#  \__/\__/\_, /\___/_//_/\_,_/_/         Please report bugs and contribute back your improvements
#         /___/
#                                         Version: v0.9.0-SNAPSHOT
#
###################################
set -euo pipefail
shopt -s inherit_errexit
unset CDPATH

if ! [[ -v dir_of_gget_gitlab ]]; then
	dir_of_gget_gitlab="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null && pwd 2>/dev/null)"
	readonly dir_of_gget_gitlab
fi
source "$dir_of_gget_gitlab/utils.sh"

# is passed to exitIfEnvVarNotSet by name
# shellcheck disable=SC2034
declare -a envVars=(
	GGET_UPDATE_API_TOKEN
	CI_API_V4_URL
	CI_PROJECT_ID
)
exitIfEnvVarNotSet envVars
readonly GGET_UPDATE_API_TOKEN CI_API_V4_URL CI_PROJECT_ID

declare gitStatus
gitStatus=$(git status --porcelain) || {
	echo "the following command failed (see above): git status --porcelain"
	exit 1
}

if [[ $gitStatus == "" ]]; then
	echo "No git changes, i.e. no updates found, no need to create a merge request"
	exit 0
fi

echo "Detected updates, going to push changes to branch gget/update"

git branch -D "gget/update" 2 &>/dev/null || true
git checkout -b "gget/update"
git add .
git commit -m "Update files pulled via gget"
git push -f --set-upstream origin gget/update || {
	echo "could not force push gget/update to origin"
	exit 1
}

declare data
data=$(
	# shellcheck disable=SC2312
	cat <<-EOM
		{
		  "source_branch": "gget/update",
		  "target_branch": "main",
		  "title": "Changes via gget update",
		  "allow_collaboration": true,
		  "remove_source_branch": true
		}
	EOM
)

echo "Going to create a merge request for the changes"

curlOutputFile=$(mktemp -t "curl-output-XXXXXXXXXX")

# passed by name to cleanupTmp
# shellcheck disable=SC2034
readonly -a tmpPaths=(curlOutputFile)
trap 'cleanupTmp tmpPaths' EXIT

statusCode=$(
	curl --request POST \
		--header "PRIVATE-TOKEN: $GGET_UPDATE_API_TOKEN" \
		--data "$data" --header "Content-Type: application/json" \
		--output "$curlOutputFile" --write-out "%{response_code}" \
		"${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests"
) || {
	echo "could not send the POST request for creating a merge request"
	exit 1
}
if [[ $statusCode = 409 ]] && grep "open merge request" "$curlOutputFile"; then
	echo "There is already a merge request, no need to create another (we force pushed, so the MR is updated)"
elif [[ ! "$statusCode" == 2* ]]; then
	printf "curl return http status code %s, expected 2xx. Message body:\n" "$statusCode"
	cat "$curlOutputFile"
	exit 1
fi
