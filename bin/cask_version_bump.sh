#!/usr/bin/env bash

# Script based on https://github.com/vitorgalvao/tiny-scripts/blob/master/cask-repair
#
# It's basically the same procedure, making it more specific to Headset with the biggest change being that the .dmg file
# is not downloaded from a URL but rather, the .dmg built by Travis is used.

set -x

# Useful variables
readonly cask_file='headset.rb'
readonly submit_pr_to='homebrew:master'
readonly cask_branch='cask_repair_update-headset'
readonly caskroom_taps_dir="$(brew --repository)/Library/Taps/homebrew"
readonly submit_pr_from="${GITHUB_USER}:${cask_branch}"
readonly installer_file="darwin/build/installers/*.dmg"
readonly cask_version=${TRAVIS_TAG:1}
readonly submission_error_log="$(mktemp)"

cd "${caskroom_taps_dir}"/homebrew-cask/Casks || exit 1

# Checks the headset remote is listed
if ! git remote | grep --silent "${GITHUB_USER}"; then
  echo "A \`${GITHUB_USER}\` remote does not exist. Creating it now…"
  hub fork --org="${GITHUB_USER}"
fi

# Create branch or checkout if it already exists
git rev-parse --verify "${cask_branch}" &>/dev/null && git checkout "${cask_branch}" --quiet || git checkout -b "${cask_branch}" --quiet

# Calculates the sha256 sum of the .dmg file
package_sha=$(shasum --algorithm 256 "${installer_file}" | awk '{ print $1 }')

# Replaces the new sha256 sum and versions into the cask file
sed -i.bak "s|version .*|version '${cask_version}'|" "${cask_file}"
sed -i.bak "s|sha256 .*|sha256 '${package_sha}'|" "${cask_file}"
rm "${cask_file}.bak"

echo "------------------------"
git --no-pager diff # Displays the difference between files
echo "------------------------"

# Submits the changes as a new PR
echo 'Submitting…'
commit_message="Update headset to ${cask_version}"
pr_message="${commit_message}\n\nAfter making all changes to the cask:\n\n- [x] \`brew cask audit --download {{cask_file}}\` is error-free.\n- [x] \`brew cask style --fix {{cask_file}}\` left no offenses.\n- [x] The commit message includes the cask’s name and version."

git commit "${cask_file}" --message "${commit_message}" --quiet
git push --force "${GITHUB_USER}" "${cask_branch}" --quiet 2> "${submission_error_log}"

# Checks if 'git push' had any errors and attempts to fix shallow-repo error
if [[ "${?}" -ne 0 ]]; then
  if grep --quiet 'shallow update not allowed' "${submission_error_log}"; then
    echo 'Push failed due to shallow repo. Unshallowing…'
    HOMEBREW_NO_AUTO_UPDATE=1 brew tap --full "homebrew/$(basename $(git remote get-url origin) '.git')"
    git push --force "${GITHUB_USER}" "${cask_branch}" --quiet 2> "${submission_error_log}"

    [[ "${?}" -ne 0 ]] && echo -e "'There were errors while pushing:'\n$(< "${submission_error_log}")"
  else
    echo -e "'There were errors while pushing:'\n$(< "${submission_error_log}")"
  fi
fi

# Submits the PR and gets a link to it
pr_link=$(hub pull-request -b "${submit_pr_to}" -h "${submit_pr_from}" -m "$(echo -e "${pr_message}")")

if [[ -n "${pr_link}" ]]; then
  echo -e "\nSubmitted (${pr_link})\n"

  # CLEANS EVERYTHING PREVIOUSLY DONE

  # Do not try to clean if not in a tap dir (e.g. if script was manually aborted too fast)
  [[ "$(dirname "$(dirname "${PWD}")")" == "${caskroom_taps_dir}" ]] || return

  current_branch="$(git rev-parse --abbrev-ref HEAD)"

  git reset HEAD --hard --quiet
  git checkout master --quiet
  git branch -D "${current_branch}" --quiet
  rm "${submission_error_log}"
else
  abort 'There was an error submitting the pull request. Please open a bug report on the repo for this script (https://github.com/vitorgalvao/tiny-scripts).'
fi
