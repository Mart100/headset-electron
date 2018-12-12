#!/usr/bin/env bash

# Script based on https://github.com/vitorgalvao/tiny-scripts/blob/master/cask-repair
#
# It's basically the same procedure, making it more specific to Headset with the biggest change being that the .dmg file
# is not downloaded from a URL but rather, the .dmg built by Travis is used.
#

set -e

# Useful variables
readonly organization='headsetapp'
readonly cask_file='headset.rb'
readonly cask_branch='cask_repair_update-headset'
readonly caskroom_taps_dir="$(brew --repository)/Library/Taps/homebrew"
readonly submit_pr_from="${organization}:${cask_branch}"
readonly installer_path="${TRAVIS_BUILD_DIR}/darwin/build/installers"
readonly installer_file="${installer_path}/$(ls ${installer_path} | grep dmg)"
readonly cask_version=${TRAVIS_TAG:1}
readonly commit_message="Update headset to ${cask_version}"
readonly pr_message="${commit_message}\n\nAfter making all changes to the cask:\n\n- [x] \`brew cask audit --download {{cask_file}}\` is error-free.\n- [x] \`brew cask style --fix {{cask_file}}\` left no offenses.\n- [x] The commit message includes the cask’s name and version."
readonly submission_error_log="$(mktemp)"

# Enable Git credential store
# echo "https://${GIHUB_TOKEN}:@github.com" > "${HOME}"/.git-credentials
# git config credential.helper "store --file=${HOME}/.git-credentials"

cd "${caskroom_taps_dir}"/homebrew-cask/Casks || exit 1

# Checks the headset remote is listed
if ! git remote | grep --silent "${organization}"; then
  echo -e "A \`${organization}\` remote does not exist. Adding it now…"
  git remote add "${organization}" "https://danielravina:${GIHUB_TOKEN}@github.com/${organization}/homebrew-cask.git" > /dev/null 2>&1
fi

# Create branch or checkout if it already exists
git rev-parse --verify "${cask_branch}" &>/dev/null && git checkout "${cask_branch}" || git checkout -b "${cask_branch}"

# Prints the current cask file
echo '--------------------'
echo "Current Headset cask file:"
echo '--------------------'
cat "${cask_file}"
echo '--------------------'

# Calculates the sha256 sum of the .dmg file
package_sha=$(shasum --algorithm 256 "${installer_file}" | awk '{ print $1 }')

# Replaces the new sha256 sum and versions into the cask file
sed -i.bak "s|version .*|version '${cask_version}'|" "${cask_file}"
sed -i.bak "s|sha256 .*|sha256 '${package_sha}'|" "${cask_file}"
rm "${cask_file}.bak"

echo -e '\n--------------------'
git --no-pager diff # Displays the difference between files
echo '--------------------'

# Error if no changes were made, submit otherwise
if git diff-index --quiet HEAD --; then
  echo 'No changes made to the cask. Exiting...'
  exit 2
else
  echo 'Submitting…'
fi

# Commits and pushes
git commit "${cask_file}" --message "${commit_message}"
echo '--------------------'
git log -1 --stat
echo '--------------------'
git status
echo '--------------------'
git push --force "${organization}" "${cask_branch}"

# Submits the PR and gets a link to it
pr_link=$(hub pull-request -b "homebrew:master" -h "${submit_pr_from}" -m "$(echo -e "${pr_message}")")

if [[ -n "${pr_link}" ]]; then
  echo -e "\nSubmitted (${pr_link})\n"
else
  echo -e 'There was an error submitting the pull request. Please open a bug report on the repo for this script (https://github.com/vitorgalvao/tiny-scripts).'
  exit 4
fi
