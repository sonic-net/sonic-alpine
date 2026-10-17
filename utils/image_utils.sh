#!/usr/bin/env bash

# Shared Azure artifact discovery and download helpers for AlpineVS images.

BUILD_API="${BUILD_API:-https://dev.azure.com/mssonic/build/_apis/build}"
CONTRIBUTION_API="${CONTRIBUTION_API:-https://dev.azure.com/mssonic/_apis/Contribution/HierarchyQuery/project/be1b070f-be15-4154-aade-b1d3bfb17054}"
DOWNLOAD_API="${DOWNLOAD_API:-https://sonic-build.azurewebsites.net/api/sonic/artifacts}"

DEFINITION_ID="${DEFINITION_ID:-1}"
BRANCH="${BRANCH:-master}"
ARTIFACT="${ARTIFACT:-sonic-buildimage.alpinevs}"
MAX_BUILDS="${MAX_BUILDS:-50}"

_require_image_commands() {
    local command

    for command in curl python3; do
        if ! command -v "$command" >/dev/null 2>&1; then
            echo "Error: required command '$command' was not found." >&2
            return 1
        fi
    done
}

_validate_output_pattern() {
    local output_pattern="$1"

    if [[ "$output_pattern" != *'{build_id}'* ]]; then
        echo "Error: output pattern must contain {build_id}." >&2
        return 1
    fi
}

_get_successful_build_ids() {
    local builds_json

    builds_json=$(
        curl -fsSL \
            --connect-timeout 30 \
            --max-time 120 \
            "$BUILD_API/builds?definitions=$DEFINITION_ID&branchName=refs/heads/$BRANCH&resultFilter=succeeded&statusFilter=completed&queryOrder=finishTimeDescending&%24top=$MAX_BUILDS&api-version=7.1"
    ) || return 1

    python3 -c '
import json
import sys

for build in json.load(sys.stdin).get("value", []):
    print(build["id"])
' <<<"$builds_json"
}

_get_artifact_metadata() {
    local build_id="$1"
    local artifacts_json

    artifacts_json=$(
        curl -fsSL \
            --connect-timeout 30 \
            --max-time 120 \
            "$BUILD_API/builds/$build_id/artifacts?api-version=7.1"
    ) || return 1

    python3 -c '
import json
import sys

artifact_name = sys.argv[1]
for artifact in json.load(sys.stdin).get("value", []):
    if artifact.get("name") == artifact_name:
        resource = artifact.get("resource", {})
        print("{}\t{}".format(artifact["id"], resource.get("downloadUrl", "")))
        break
' "$ARTIFACT" <<<"$artifacts_json"
}

_artifact_contains_path() {
    local build_id="$1"
    local artifact_id="$2"
    local target_path="$3"
    local manifest_request
    local manifest_json

    manifest_request=$(printf '%s' \
        "{\"contributionIds\":[\"ms.vss-build-web.run-artifacts-data-provider\"],\"dataProviderContext\":{\"properties\":{\"artifactId\":$artifact_id,\"buildId\":$build_id,\"sourcePage\":{\"url\":\"https://dev.azure.com/mssonic/build/_build/results?buildId=$build_id&view=artifacts&pathAsName=false&type=publishedArtifacts\",\"routeValues\":{\"project\":\"build\",\"action\":\"Execute\"}}}}}")

    manifest_json=$(
        curl -fsSL \
            --connect-timeout 30 \
            --max-time 120 \
            -X POST \
            -H 'Accept: application/json;api-version=5.0-preview.1' \
            -H 'Content-Type: application/json' \
            --data "$manifest_request" \
            "$CONTRIBUTION_API"
    ) || return 2

    python3 -c '
import json
import sys

expected = "/" + sys.argv[1].lstrip("/")

def contains_path(value):
    if isinstance(value, dict):
        if value.get("name") == expected:
            return True
        return any(contains_path(child) for child in value.values())
    if isinstance(value, list):
        return any(contains_path(child) for child in value)
    return False

sys.exit(0 if contains_path(json.load(sys.stdin)) else 1)
' "$target_path" <<<"$manifest_json"
}

_download_to_file() {
    local output_file="$1"
    local partial_file="${output_file}.part"
    shift

    if curl -fL \
        --retry 100 \
        --retry-delay 5 \
        --retry-all-errors \
        --connect-timeout 60 \
        --speed-limit 1024 \
        --speed-time 60 \
        -o "$partial_file" \
        "$@"; then
        mv -f -- "$partial_file" "$output_file"
        echo "Download complete: $(pwd)/$output_file"
        return 0
    fi

    return 1
}

download_official_image_file() {
    local target_path="$1"
    local output_pattern="$2"
    local build_ids_text
    local build_id
    local metadata
    local artifact_id
    local artifact_url
    local output_file
    local manifest_status
    local found_image=false

    _require_image_commands || return 1
    _validate_output_pattern "$output_pattern" || return 1

    if ! build_ids_text=$(_get_successful_build_ids); then
        echo "Error: could not list successful builds for definition $DEFINITION_ID on branch $BRANCH." >&2
        return 1
    fi
    if [[ -z "$build_ids_text" ]]; then
        echo "Error: no successful builds found for definition $DEFINITION_ID on branch $BRANCH." >&2
        return 1
    fi

    while IFS= read -r build_id; do
        echo "Checking build $build_id..."

        if ! metadata=$(_get_artifact_metadata "$build_id"); then
            echo "Warning: could not open the Artifacts page for build $build_id; trying the next build." >&2
            continue
        fi
        if [[ -z "$metadata" ]]; then
            echo "Build $build_id does not contain artifact $ARTIFACT; trying the next build."
            continue
        fi

        IFS=$'\t' read -r artifact_id artifact_url <<<"$metadata"
        if _artifact_contains_path "$build_id" "$artifact_id" "$target_path"; then
            manifest_status=0
        else
            manifest_status=$?
        fi
        if ((manifest_status == 2)); then
            echo "Warning: could not read artifact $ARTIFACT from build $build_id; trying the next build." >&2
            continue
        fi
        if ((manifest_status != 0)); then
            echo "Build $build_id does not contain $target_path; trying the next build."
            continue
        fi

        found_image=true
        output_file="${output_pattern//\{build_id\}/$build_id}"

        echo "Found $target_path in build $build_id."
        echo "Downloading $output_file..."

        if _download_to_file "$output_file" \
            --get \
            --data-urlencode "branchName=$BRANCH" \
            --data-urlencode "definitionId=$DEFINITION_ID" \
            --data-urlencode "buildId=$build_id" \
            --data-urlencode "artifactName=$ARTIFACT" \
            --data-urlencode "target=$target_path" \
            "$DOWNLOAD_API"; then
            return 0
        fi

        echo "Warning: download from build $build_id failed; trying the next build." >&2
    done <<<"$build_ids_text"

    if [[ "$found_image" == true ]]; then
        echo "Error: $target_path was found, but every download attempt failed." >&2
    else
        echo "Error: $target_path was not available in the newest $MAX_BUILDS successful builds." >&2
    fi
    return 1
}

download_official_artifact_archive() {
    local output_pattern="$1"
    local build_ids_text
    local build_id
    local metadata
    local artifact_id
    local artifact_url
    local output_file
    local found_artifact=false

    _require_image_commands || return 1
    _validate_output_pattern "$output_pattern" || return 1

    if ! build_ids_text=$(_get_successful_build_ids); then
        echo "Error: could not list successful builds for definition $DEFINITION_ID on branch $BRANCH." >&2
        return 1
    fi
    if [[ -z "$build_ids_text" ]]; then
        echo "Error: no successful builds found for definition $DEFINITION_ID on branch $BRANCH." >&2
        return 1
    fi

    while IFS= read -r build_id; do
        echo "Checking build $build_id..."

        if ! metadata=$(_get_artifact_metadata "$build_id"); then
            echo "Warning: could not open the Artifacts page for build $build_id; trying the next build." >&2
            continue
        fi
        if [[ -z "$metadata" ]]; then
            echo "Build $build_id does not contain artifact $ARTIFACT; trying the next build."
            continue
        fi

        IFS=$'\t' read -r artifact_id artifact_url <<<"$metadata"
        if [[ -z "$artifact_url" ]]; then
            echo "Warning: artifact $ARTIFACT in build $build_id has no download URL; trying the next build." >&2
            continue
        fi

        found_artifact=true
        output_file="${output_pattern//\{build_id\}/$build_id}"

        echo "Found artifact $ARTIFACT in build $build_id."
        echo "Downloading $output_file..."

        if _download_to_file "$output_file" "$artifact_url"; then
            return 0
        fi

        echo "Warning: download from build $build_id failed; trying the next build." >&2
    done <<<"$build_ids_text"

    if [[ "$found_artifact" == true ]]; then
        echo "Error: $ARTIFACT was found, but every download attempt failed." >&2
    else
        echo "Error: $ARTIFACT was not available in the newest $MAX_BUILDS successful builds." >&2
    fi
    return 1
}
