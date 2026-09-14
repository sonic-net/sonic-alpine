#!/usr/bin/env bash
set -euo pipefail


#Script to download the official alpine build from Github 

API="https://dev.azure.com/mssonic/build/_apis/build"

# DEFINITION_ID = 1 to download alpine from sonic-buildimage master build, 
# DEFINITION_ID = 3412 to download alpine from the alpine official build
# Both are practically the same
DEFINITION_ID="1"
BRANCH="master"
ARTIFACT="sonic-buildimage.alpinevs"
IMAGE="target/sonic-alpinevs.img.gz"

BUILD_ID=$(
  curl -fsSL \
    "$API/builds?definitions=$DEFINITION_ID&branchName=refs/heads/$BRANCH&resultFilter=succeeded&queryOrder=finishTimeDescending&%24top=1&api-version=7.1" | jq -er '.value[0].id'
)

ZIP_URL=$(
   curl -fsSL "$API/builds/$BUILD_ID/artifacts?artifactName=$ARTIFACT&api-version=7.1" |   jq -er '.resource.downloadUrl'
)

echo "Build ID: $BUILD_ID"
echo "Artifact ZIP URL: $ZIP_URL"

OUTPUT_FILE="${ARTIFACT}-${BUILD_ID}.zip"
echo "Downloading $OUTPUT_FILE..."

curl -L -C - \
  --retry 100 \
  --retry-delay 5 \
  --retry-all-errors \
  --connect-timeout 60 \
  -o "$OUTPUT_FILE" \
  "$ZIP_URL"

echo "Download complete: $(pwd)/$OUTPUT_FILE"
