#!/bin/bash

#=================================================
# PACKAGE UPDATING HELPER
#=================================================

# This script is meant to be run by GitHub Actions
# The YunoHost-Apps organisation offers a template Action to run this script periodically
# Since each app is different, maintainers can adapt its contents so as to perform
# automatic actions when a new upstream release is detected.

#=================================================
# FETCHING LATEST RELEASE AND ITS ASSETS
#=================================================

# Fetching information
current_version=$(cat manifest.json | jq -j '.version|split("~")[0]')
current_ynh_version=$(cat manifest.json | jq -j '.version|split("~ynh")[1]')
current_commit=$(cat scripts/_common.sh | awk -F= '/^COMMIT/ { print $2 }')
repo=$(cat manifest.json | jq -j '.upstream.code|split("https://github.com/")[1]')

page=0
tag_version=""
while [ -z $tag_version ]
do
    let page++
    tag_version=$(curl --silent "https://api.github.com/repos/$repo/tags?per_page=100&page=$page" | jq -r '.[] | .name' | grep -v "alpha" | grep "@standardnotes/web@" | sort -V | tail -1)

done

version=$(curl --silent "https://raw.githubusercontent.com/$repo/$tag_version/packages/web/package.json" | jq -j '.version')
asset="https://github.com/$repo/archive/refs/tags/$tag_version.tar.gz"
commit=$(curl --silent "https://api.github.com/repos/$repo/tags?per_page=100&page=$page" | jq -r '[ .[] | select(.name=="'$tag_version'").commit.sha ] | join(" ") | @sh' | tr -d "'")

# Later down the script, we assume the version has only digits and dots
# Sometimes the release name starts with a "v", so let's filter it out.
# You may need more tweaks here if the upstream repository has different naming conventions.
#if [[ ${version:0:1} == "v" || ${version:0:1} == "V" ]]; then
#    version=${version:1}
#fi

# Setting up the environment variables
echo "Current version: $current_version"
echo "Current ynh version: $current_ynh_version"
echo "Current commit: $current_commit"
echo "Latest tag version from upstream: $tag_version"
echo "Latest version from upstream: $version"

echo "VERSION=$version" >> $GITHUB_ENV
echo "YNH_VERSION=$current_ynh_version" >> $GITHUB_ENV
echo "TAG_VERSION=$tag_version" >> $GITHUB_ENV
# For the time being, let's assume the script will fail
echo "PROCEED=false" >> $GITHUB_ENV

# Proceed only if the retrieved version is greater than the current one
if [[ ${current_commit:1:-1} == $commit ]] ; then
    echo "::warning ::No new version available"
    exit 0
# Proceed only if a PR for this new version does not already exist
elif git ls-remote -q --exit-code --heads https://github.com/$GITHUB_REPOSITORY.git ci-auto-update-v$version-tag$tag_version ; then
    echo "::warning ::A branch already exists for this update"
    exit 0
fi

#=================================================
# UPDATE SOURCE FILES
#=================================================

# Create the temporary directory
tempdir="$(mktemp -d)"

# Download sources and calculate checksum
filename=${asset##*/}
curl --silent -4 -L $asset -o "$tempdir/$filename"
checksum=$(sha256sum "$tempdir/$filename" | head -c 64)

# Delete temporary directory
rm -rf $tempdir

# Get extension
if [[ $filename == *.tar.gz ]]; then
  extension=tar.gz
else
  extension=${filename##*.}
fi

# Rewrite source file
cat <<EOT > conf/app.src
SOURCE_URL=$asset
SOURCE_SUM=$checksum
SOURCE_SUM_PRG=sha256sum
SOURCE_FORMAT=$extension
SOURCE_IN_SUBDIR=true
SOURCE_FILENAME=
EOT
echo "... conf/app.src updated"

#=================================================
# SPECIFIC UPDATE STEPS
#=================================================

# Any action on the app's source code can be done.
# The GitHub Action workflow takes care of committing all changes after this script ends.

#=================================================
# GENERIC FINALIZATION
#=================================================

if ! dpkg --compare-versions "$current_version" "lt" "$version" ; then
	new_version="$version~ynh$((current_ynh_version+1))"
else
	new_version="$version~ynh1"
fi

# Replace new version in manifest
echo "$(jq -s --indent 4 ".[] | .version = \"$new_version\"" manifest.json)" > manifest.json

# No need to update the README, yunohost-bot takes care of it

# The Action will proceed only if the PROCEED environment variable is set to true
echo "PROCEED=true" >> $GITHUB_ENV
exit 0
