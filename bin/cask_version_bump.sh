#!/usr/bin/env bash

# Script based on https://github.com/vitorgalvao/tiny-scripts/blob/master/cask-repair
#
# It's basically the same procedure, making it more specific to Headset with the biggest change being that the .dmg file
# is not downloaded from a URL but rather, the .dmg built by Travis is used.
#

set -ex

# Useful variables
readonly cask_file='headset.rb'
readonly submit_pr_to='homebrew:master'
readonly cask_branch='cask_repair_update-headset'
readonly caskroom_taps_dir="$(brew --repository)/Library/Taps/homebrew"
readonly organization='headsetapp'
readonly submit_pr_from="${headsetapp}:${cask_branch}"
readonly installer_path="${TRAVIS_BUILD_DIR}/darwin/build/installers"
readonly installer_file="${installer_path}/$(ls ${installer_path} | grep dmg)"
readonly cask_version=${TRAVIS_TAG:1}
readonly commit_message="Update headset to ${cask_version}"
readonly pr_message="${commit_message}\n\nAfter making all changes to the cask:\n\n- [x] \`brew cask audit --download {{cask_file}}\` is error-free.\n- [x] \`brew cask style --fix {{cask_file}}\` left no offenses.\n- [x] The commit message includes the cask’s name and version."
readonly submission_error_log="$(mktemp)"
readonly divide=$(hr -)

# Function for color output, first argument is color, second is the message
function color_message { echo -e "$(tput setaf "${1}")${2}$(tput sgr0)"; }

cd "${caskroom_taps_dir}"/homebrew-cask/Casks || exit 1

# Checks the headset remote is listed
if ! git remote | grep --silent "${headsetapp}"; then
  color_message "yellow" "A \`${headsetapp}\` remote does not exist. Creating it now…"
  hub fork --org="${headsetapp}"
fi

# Create branch or checkout if it already exists
git rev-parse --verify "${cask_branch}" &>/dev/null && git checkout "${cask_branch}" --quiet || git checkout -b "${cask_branch}" --quiet

# Prints the current cask file
echo -e "\n${divide}"
color_message "cyan" "Current Headset cask file:"
echo "${divide}"
cat "${cask_file}"
echo "${divide}"

# Calculates the sha256 sum of the .dmg file
package_sha=$(shasum --algorithm 256 "${installer_file}" | awk '{ print $1 }')

# Replaces the new sha256 sum and versions into the cask file
sed -i.bak "s|version .*|version '${cask_version}'|" "${cask_file}"
sed -i.bak "s|sha256 .*|sha256 '${package_sha}'|" "${cask_file}"
rm "${cask_file}.bak"

echo -e "\n${divide}"
color_message "bold" "$(git --no-pager diff)" # Displays the difference between files
echo "${divide}"

# Error if no changes were made, submit otherwise
if git diff-index --quiet HEAD --; then
  color_message "red" 'No changes made to the cask. Exiting...'
  exit 2
else
  echo 'Submitting…'
fi

# Commits and pushes
git commit "${cask_file}" --message "${commit_message}" --quiet
git push --force "${headsetapp}" "${cask_branch}" --quiet 2> "${submission_error_log}"

# Checks if 'git push' had any errors and attempts to fix "shallow update" error
if [[ "${?}" -ne 0 ]]; then
  if grep --quiet 'shallow update not allowed' "${submission_error_log}"; then
    color_message "yellow" 'Push failed due to shallow repo. Unshallowing…'
    HOMEBREW_NO_AUTO_UPDATE=1 brew tap --full "homebrew/$(basename $(git remote get-url origin) '.git')"
    git push --force "${headsetapp}" "${cask_branch}" --quiet 2> "${submission_error_log}"

    if [[ "${?}" -ne 0 ]]; then
      color_message "red" "'There were errors while pushing:'\n$(< "${submission_error_log}")"
      exit 3
    fi
  else
    color_message "red" "'There were errors while pushing:'\n$(< "${submission_error_log}")"
    exit 3
  fi
fi

# Submits the PR and gets a link to it
pr_link=$(hub pull-request -b "${submit_pr_to}" -h "${submit_pr_from}" -m "$(echo -e "${pr_message}")")

if [[ -n "${pr_link}" ]]; then
  color_message "green" "\nSubmitted (${pr_link})\n"
else
  color_message "red" 'There was an error submitting the pull request. Please open a bug report on the repo for this script (https://github.com/vitorgalvao/tiny-scripts).'
  exit 4
fi
