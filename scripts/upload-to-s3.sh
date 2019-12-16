#!/usr/bin/env bash

# ----- Helper functions ----- #

is_edge ()
{
	[[ "${TRAVIS_BRANCH}" == "develop" ]]
}

is_stable ()
{
	[[ "${TRAVIS_BRANCH}" == "master" ]]
}

is_release ()
{
	[[ "${TRAVIS_TAG}" != "" ]]
}

# Check whether the current build is for a pull request
is_pr ()
{
	[[ "${TRAVIS_PULL_REQUEST}" != "false" ]]
}
# ---------------------------- #

# Extract version parts from release tag
IFS='.' read -a ver_arr <<< "$TRAVIS_TAG"
VERSION_MAJOR=${ver_arr[0]#v*}  # 2.7.0 => "2"
VERSION_MINOR=${ver_arr[1]}  # "2.7.0" => "7"

EDGE_UPLOAD_DIR=${UPLOAD_DIR}/edge
STABLE_UPLOAD_DIR=${UPLOAD_DIR}/stable
RELEASE_UPLOAD_DIR=${UPLOAD_DIR}/v${VERSION_MAJOR}.${VERSION_MINOR}

# Skip pull request
is_pr && exit 0

# Upload templates
if is_edge; then
	aws s3 cp ${LOCAL_DIR}/${TEMPLATE_TYPE}.yaml s3://${S3_BUCKET}/${EDGE_UPLOAD_DIR}/${TEMPLATE_TYPE}.yaml --acl public-read
elif is_stable; then
	aws s3 cp ${LOCAL_DIR}/${TEMPLATE_TYPE}.yaml s3://${S3_BUCKET}/${STABLE_UPLOAD_DIR}/${TEMPLATE_TYPE}.yaml --acl public-read
elif is_release; then
	aws s3 cp ${LOCAL_DIR}/${TEMPLATE_TYPE}.yaml s3://${S3_BUCKET}/${RELEASE_UPLOAD_DIR}/${TEMPLATE_TYPE}.yaml --acl public-read
else
	# Exit if not on develop, master or release tag
	exit 0
fi
