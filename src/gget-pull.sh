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
#  'pull' command of gget: utility to pull files from a previously defined git remote repository
#
#######  Usage  ###################
#
#    #!/usr/bin/env bash
#
#    # pull the file src/utility/update-bash-docu.sh from remote tegonal-scripts
#    # in version v0.1.0 (i.e. tag v0.1.0 is used)
#    gget pull -r tegonal-scripts -t v0.1.0 -p src/utility/update-bash-docu.sh
#
#    # pull the directory src/utility/ from remote tegonal-scripts
#    # in version v0.1.0 (i.e. tag v0.1.0 is used)
#    gget pull -r tegonal-scripts -t v0.1.0 -p src/utility/
#
###################################
set -euo pipefail
shopt -s inherit_errexit
export GGET_VERSION='v0.2.0-SNAPSHOT'

if ! [[ -v dir_of_gget ]]; then
	dir_of_gget="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null && pwd 2>/dev/null)"
	declare -r dir_of_gget
fi

if ! [[ -v dir_of_tegonal_scripts ]]; then
	dir_of_tegonal_scripts="$dir_of_gget/../lib/tegonal-scripts/src"
	source "$dir_of_tegonal_scripts/setup.sh" "$dir_of_tegonal_scripts"
fi

sourceOnce "$dir_of_gget/pulled-utils.sh"
sourceOnce "$dir_of_gget/utils.sh"
sourceOnce "$dir_of_tegonal_scripts/utility/gpg-utils.sh"
sourceOnce "$dir_of_tegonal_scripts/utility/io.sh"
sourceOnce "$dir_of_tegonal_scripts/utility/parse-args.sh"

function gget_pull_cleanupRepo() {
	local -r repository=$1
	find "$repository" -maxdepth 1 -type d -not -path "$repository" -not -name ".git" -exec rm -r {} \;
}

function gget_pull() {
	local startTime endTime elapsed
	startTime=$(date +%s.%3N)

	source "$dir_of_gget/shared-patterns.source.sh" || die "was not able to source shared-patterns.source.sh"
	local -r UNSECURE_NO_VERIFY_PATTERN='--unsecure-no-verification'

	local currentDir
	currentDir=$(pwd)
	local -r currentDir

	local remote tag path pullDir chopPath workingDir autoTrust unsecure forceNoVerification
	# shellcheck disable=SC2034
	local -ra params=(
		remote "$remotePattern" 'name of the remote repository'
		tag '-t|--tag' 'git tag used to pull the file/directory'
		path '-p|--path' 'path in remote repository which shall be pulled (file or directory)'
		pullDir "$pullDirPattern" "(optional) directory into which files are pulled -- default: pull directory of this remote (defined during \"remote add\" and stored in $defaultWorkingDir/<remote>/pull.args)"
		chopPath "--chop-path" '(optional) if set to true, then files are put into the pull directory without the path specified. For files this means they are put directly into the pull directory'
		workingDir "$workingDirPattern" "$workingDirParamDocu"
		autoTrust "$autoTrustPattern" "$autoTrustParamDocu"
		unsecure "$unsecurePattern" "(optional) if set to true, the remote does not need to have GPG key(s) defined in gpg databse or at $defaultWorkingDir/<remote>/*.asc -- default: false"
		forceNoVerification "$UNSECURE_NO_VERIFY_PATTERN" "(optional) if set to true, implies $unsecurePattern true and does not verify even if gpg keys are in store or at $defaultWorkingDir/<remote>/*.asc -- default: false"
	)

	local -r examples=$(
		# shellcheck disable=SC2312
		cat <<-EOM
			# pull the file src/utility/update-bash-docu.sh from remote tegonal-scripts
			# in version v0.1.0 (i.e. tag v0.1.0 is used)
			gget pull -r tegonal-scripts -t v0.1.0 -p src/utility/update-bash-docu.sh

			# pull the directory src/utility/ from remote tegonal-scripts
			# in version v0.1.0 (i.e. tag v0.1.0 is used)
			gget pull -r tegonal-scripts -t v0.1.0 -p src/utility/

			# pull the file .github/CODE_OF_CONDUCT.md and put it into the pull directory .github
			# without repeating the path (option --chop-path), i.e is pulled directly into .github/CODE_OF_CONDUCT.md
			# and not into .github/.github/CODE_OF_CONDUCT.md
			gget pull -r tegonal-scripts -t v0.1.0 -d .github --chop-path true -p .github/CODE_OF_CONDUCT.md
		EOM
	)

	# parsing once so that we get workingDir and remote
	# redirecting output to /dev/null because we don't want to see 'ignored argument warnings' twice
	# || true because --help returns 99 and we don't want to exit at this point (because we redirect output)
	parseArguments params "$examples" "$GGET_VERSION" "$@" >/dev/null || true
	if ! [[ -v workingDir ]]; then workingDir="$defaultWorkingDir"; fi

	local -a args=()
	if [[ -v remote ]] && [[ -n $remote ]]; then
		# cannot be readonly as we override it in paths.source.sh as well, should be the same though
		local pullArgsFile="$workingDir/remotes/$remote/pull.args"
		if [[ -f $pullArgsFile ]]; then
			local defaultArguments
			defaultArguments=$(cat "$pullArgsFile") || die "could not read %s, you might not execute what you want without it, aborting" "$pullArgsFile"
			eval 'for arg in '"$defaultArguments"'; do
					args+=("$arg");
			done'
		fi
	fi
	args+=("$@")
	parseArguments params "$examples" "$GGET_VERSION" "${args[@]}"

	if ! [[ -v chopPath ]]; then chopPath=false; fi
	if ! [[ -v autoTrust ]]; then autoTrust=false; fi
	if ! [[ -v forceNoVerification ]]; then forceNoVerification=false; fi
	if ! [[ -v unsecure ]]; then unsecure="$forceNoVerification"; fi

	# if remote does not exist then pull.args does not and most likely pullDir is thus not defined, in this case we want
	# to show the error about the non existing remote before other missing arguments
	if ! [[ -v pullDir ]] && [[ -v workingDir ]] && [[ -v remote ]]; then
		exitIfRemoteDirDoesNotExist "$workingDir" "$remote"
	fi
	checkAllArgumentsSet params "$examples" "$GGET_VERSION"

	local workingDirAbsolute pullDirAbsolute
	workingDirAbsolute=$(readlink -m "$workingDir")
	pullDirAbsolute=$(readlink -m "$pullDir")
	local -r workingDirAbsolute pullDirAbsolute

	exitIfWorkingDirDoesNotExist "$workingDirAbsolute"
	exitIfRemoteDirDoesNotExist "$workingDirAbsolute" "$remote"

	local remoteDir publicKeysDir repo gpgDir pulledTsv gitconfig
	source "$dir_of_gget/paths.source.sh"

	if ! [[ -d $pullDirAbsolute ]]; then
		mkdir -p "$pullDirAbsolute" || die "failed to create the pull directory %s" "$pullDirAbsolute"
	fi

	if ! [[ -f $pulledTsv ]]; then
		pulledTsvHeader >"$pulledTsv" || die "failed to initialise the pulled.tsv file at %s" "$pulledTsv"
	else
		exitIfHeaderOfPulledTsvIsWrong "$pulledTsv"
	fi

	if [[ -f $repo ]]; then
		die "looks like the remote \033[0;36m%s\033[0m is broken there is a file at the repo's location: %s" "$remote" "$remoteDir"
	elif ! [[ -d "$repo/.git" ]]; then
		logInfo "repo directory (or its .git directory) does not exist for remote \033[0;36m%s\033[0m. We are going to re-initialise it based on the stored gitconfig" "$remote"
		reInitialiseGitDir "$workingDir" "$remote"
	fi

	local doVerification
	if [[ $forceNoVerification == true ]]; then
		doVerification=false
	else
		doVerification=true
		if ! [[ -d $gpgDir ]]; then
			if [[ -f $gpgDir ]]; then
				die "looks like the remote \033[0;36m%s\033[0m is broken there is a file at the gpg dir's location: %s" "$remote" "$gpgDir"
			fi

			logInfo "gpg directory does not exist at %s\nWe are going to import all public keys which are stored in %s" "$gpgDir" "$publicKeysDir"

			if noAscInDir "$publicKeysDir"; then
				if [[ $unsecure == true ]]; then
					logWarning "no GPG key found, won't be able to verify files (which is OK because %s true was specified)" "$unsecurePattern"
					doVerification=false
				else
					die "no public keys for remote \033[0;36m%s\033[0m defined in %s" "$remote" "$publicKeysDir"
				fi
			else
				initialiseGpgDir "$gpgDir"
				local confirm
				confirm="--confirm=$(invertBool "$autoTrust")"

				local -i numberOfImportedKeys=0
				function gget_pull_importGpgKeys() {
					findAscInDir "$publicKeysDir" -print0 >&3
					local file
					while read -u 4 -r -d $'\0' file; do
						if importGpgKey "$gpgDir" "$file" "$confirm"; then
							((++numberOfImportedKeys))
						fi
					done
				}
				withCustomOutputInput 3 4 gget_pull_importGpgKeys
				if ((numberOfImportedKeys == 0)); then
					if [[ $unsecure == true ]]; then
						logWarning "all GPG keys declined, won't be able to verify files (which is OK because %s true was specified)" "$unsecurePattern"
						doVerification=false
					else
						exitBecauseNoGpgKeysImported "$remote" "$publicKeysDir" "$gpgDir" "$unsecurePattern"
					fi
				fi
			fi
		fi
		if [[ $unsecure == true && $doVerification == true ]]; then
			logInfo "gpg key found going to perform verification even though %s true was specified" "$unsecurePattern"
		fi
	fi

	# we want to expand $repo here and not when signal happens (as $repo might be out of scope)
	# shellcheck disable=SC2064
	trap "gget_pull_cleanupRepo '$repo'" EXIT SIGINT

	cd "$repo"
	if ! git remote | grep "$remote" >/dev/null; then
		logError "looks like the .git directory of remote %s is broken. There is no remote %s setup." "$remote" "$remote"
		if [[ -f $gitconfig ]]; then
			if askYesOrNo "Shall I delete the repo and re-initialise it based on %s" "$gitconfig"; then
				# cd only necessary because we did a cd $repo beforehand, could be removed if we don't do it
				cd "$workingDir"
				deleteDirChmod777 "$repo"
				reInitialiseGitDir "$workingDir" "$remote"
				# cd only necessary because we did a cd $repo and then cd $workingDir beforehand, could be removed if we don't do it
				cd "$repo"
			else
				exit 1
			fi
		else
			logInfo >&2 "%s does not exist, cannot ask to re-initialise the repo, must abort" "$gitconfig"
			exit 1
		fi
	fi
	local tags
	tags=$(git tag) || die "The following command failed (see above): git tag"
	if grep "$tag" <<<"$tags" >/dev/null; then
		logInfo "tag %s already exists locally, skipping fetching from remote" "$tag"
	else
		local remoteTags
		remoteTags=$(git ls-remote -t "$remote") || (logInfo >&2 "check your internet connection" && return 1) || return $?
		grep "$tag" <<<"$remoteTags" >/dev/null || returnDying "remote \033[0;36m%s\033[0m does not have the tag \033[0;36m%s\033[0m\nFollowing the available tags:\n%s" "$remote" "$tag" "$remoteTags" || return $?
		git fetch --depth 1 "$remote" "refs/tags/$tag:refs/tags/$tag" || returnDying "was not able to fetch tag %s from remote %s" "$tag" "$remote" || return $?
	fi

	git checkout "tags/$tag" -- "$path" || return $?

	function gget_pull_mentionUnsecure() {
		if ! [[ $unsecure == true ]]; then
			printf " -- you can disable this check via %s true\n" "$unsecurePattern"
		else
			printf " -- you can disable this check via %s true\n" "$UNSECURE_NO_VERIFY_PATTERN"
		fi
	}

	local -r sigExtension="sig"

	function gget_pull_pullSignatureOfSingleFetchedFile() {
		# is path a file then fetch also the corresponding signature
		if [[ $doVerification == true && -f "$repo/$path" ]]; then
			if ! git checkout "tags/$tag" -- "$path.$sigExtension"; then
				logErrorWithoutNewline "no signature file found for %s, aborting pull" "$path"
				gget_pull_mentionUnsecure >&2
				return 1
			fi
		fi
	}
	gget_pull_pullSignatureOfSingleFetchedFile

	local -i numberOfPulledFiles=0

	function gget_pull_moveFile() {
		local file=$1

		local targetFile
		if [[ $chopPath == true ]]; then
			if [[ -d "$repo/$path" ]]; then
				local offset
				offset=$(if [[ $path == */ ]]; then echo 1; else echo 2; fi)
				targetFile="$(cut -c "$((${#path} + offset))"- <<<"$file")" || returnDying "could not calculate the target file for \033[0;36m%s\033[0m" "$file" || return $?
			else
				targetFile="$(basename "$file")" || returnDying "could not calculate the target file for \033[0;36m%s\033[0m" "$file" || return $?
			fi
		else
			targetFile="$file"
		fi
		local -r absoluteTarget="$pullDirAbsolute/$targetFile"
		local parentDir
		parentDir=$(dirname "$absoluteTarget")
		# parent dir needs to be created before relativeTarget is determined because realpath expects an existing parent dir
		mkdir -p "$parentDir" || die "was not able to create the parent dir for %s" "$absoluteTarget"

		local relativeTarget sha entry currentEntry
		relativeTarget=$(realpath --relative-to="$workingDirAbsolute" "$absoluteTarget") || returnDying "could not determine relativeTarget for \033[0;36m%s\033[0m" "$absoluteTarget" || return $?
		sha=$(sha512sum "$repo/$file" | cut -d " " -f 1) || returnDying "could not calculate sha12 for \033[0;36m%s\033[0m" "$repo/$file" || return $?
		entry=$(pulledTsvEntry "$tag" "$file" "$relativeTarget" "$sha") || returnDying "could not create pulled.tsv entry for tag %s and file \033[0;36m%s\033[0m" "$tag" "$file" || return $?
		# perfectly fine if there is no entry, we return an empty string in this case for which we check further below
		currentEntry=$(grepPulledEntryByFile "$pulledTsv" "$file" || echo "")
		local -r relativeTarget sha entry currentEntry

		local entryTag entrySha entryRelativePath
		setEntryVariables "$currentEntry"
		local -r entryTag entrySha entryRelativePath

		if [[ $currentEntry == "" ]]; then
			echo "$entry" >>"$pulledTsv" || die "was not able to append the entry for file %s to \033[0;36m%s\033[0m" "$file" "$pulledTsv"
		elif ! [[ $entryTag == "$tag" ]]; then
			logInfo "the file was pulled before in version %s, going to override with version %s \033[0;36m%s\033[0m" "$entryTag" "$tag" "$file"
			# we could warn about a version which was older
			replacePulledEntry "$pulledTsv" "$file" "$entry"
		else
			if ! [[ $entrySha == "$sha" ]]; then
				logWarning "looks like the sha512 of \033[0;36m%s\033[0m changed in tag %s" "$file" "$tag"
				gitDiffChars "$entrySha" "$sha"
				printf "Won't pull the file, remove the entry from %s if you want to pull it nonetheless\n" "$pulledTsv"
				rm "$repo/$file"
				return
			elif ! grep --line-regexp "$entry" "$pulledTsv" >/dev/null; then
				local currentLocation newLocation
				currentLocation=$(realpath --relative-to="$currentDir" "$workingDirAbsolute/$entryRelativePath" || echo "$workingDirAbsolute/$entryRelativePath")
				newLocation=$(realpath --relative-to="$currentDir" "$pullDir/$targetFile" || echo "$pullDir/$targetFile")
				local -r currentLocation newLocation
				logWarning "the file was previously pulled to a different location"
				echo "current location: $currentLocation"
				echo "    new location: $newLocation"
				printf "Won't pull the file again, remove the entry from %s if you want to pull it nonetheless\n" "$pulledTsv"
				rm "$repo/$file"
				return
			elif [[ -f $absoluteTarget ]]; then
				logInfo "the file was pulled before to the same location, going to override \033[0;36m%s\033[0m" "$absoluteTarget"
			fi
		fi

		mv "$repo/$file" "$absoluteTarget" || returnDying "was not able to move the file \033[0;36m%s\033[0m to %s" "$repo/$file" "$absoluteTarget" || return $?

		((++numberOfPulledFiles))
	}

	local file
	while read -r -d $'\0' file; do
		if [[ $doVerification == true && -f "$file.$sigExtension" ]]; then
			printf "verifying \033[0;36m%s\033[0m\n" "$file"
			if [[ -d "$pullDirAbsolute/$file" ]]; then
				die "there exists a directory with the same name at %s" "$pullDirAbsolute/$file"
			fi
			gpg --homedir="$gpgDir" --verify "$file.$sigExtension" "$file" || returnDying "gpg verification failed for file \033[0;36m%s\033[0m" "$file" || return $?
			# or true as we will try to cleanup the repo on exit
			rm "$file.$sigExtension" || true
			gget_pull_moveFile "$file"
		elif [[ $doVerification == true ]]; then
			logWarningWithoutNewline "there was no corresponding *.%s file for %s, skipping it" "$sigExtension" "$file"
			gget_pull_mentionUnsecure
			# or true as we will try to cleanup the repo on exit
			rm "$file" || true
		else
			gget_pull_moveFile "$file"
		fi
	done < <(find "$path" -type f -not -name "*.$sigExtension" -print0 ||
		# `while read` will fail because there is no \0
		true)

	endTime=$(date +%s.%3N)
	elapsed=$(bc <<<"scale=3; $endTime - $startTime")
	if ((numberOfPulledFiles > 1)); then
		logSuccess "%s files pulled from %s %s in %s seconds" "$numberOfPulledFiles" "$remote" "$path" "$elapsed"
	elif ((numberOfPulledFiles = 1)); then
		logSuccess "file %s pulled from %s in %s seconds" "$path" "$remote" "$elapsed"
	else
		returnDying "0 files could be pulled from %s, most likely verification failed, see above." "$remote"
	fi
}

${__SOURCED__:+return}
gget_pull "$@"
