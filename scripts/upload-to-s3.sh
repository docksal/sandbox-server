#!/usr/bin/env bash

# ----- Helper functions ----- #

is_edge ()
{
	[[ "${GITHUB_REF}" == "refs/heads/develop" ]]
}

is_stable ()
{
	[[ "${GITHUB_REF}" == "refs/heads/master" ]]
}

is_release ()
{
	[[ "${GITHUB_REF}" =~ "refs/tags/" ]]
}

# Check whether the current build is for a pull request
is_pr ()
{
	# GITHUB_HEAD_REF is only set for pull requests
	[[ "${GITHUB_HEAD_REF}" != "" ]]
}
# ---------------------------- #

# Extract version parts from release tag
IFS='.' read -a ver_arr <<< ${GITHUB_REF#refs/tags/}
VERSION_MAJOR=${ver_arr[0]#v*}  # 2.7.0 => "2"
VERSION_MINOR=${ver_arr[1]}  # "2.7.0" => "7"
VERSION_HOTFIX=${ver_arr[2]}  # "2.7.0" => "0"

EDGE_UPLOAD_DIR=${UPLOAD_DIR}/edge
STABLE_UPLOAD_DIR=${UPLOAD_DIR}/stable
RELEASE_UPLOAD_DIR_MAJOR=${UPLOAD_DIR}/v${VERSION_MAJOR}
RELEASE_UPLOAD_DIR_MINOR=${UPLOAD_DIR}/v${VERSION_MAJOR}.${VERSION_MINOR}
RELEASE_UPLOAD_DIR_HOTFIX=${UPLOAD_DIR}/v${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_HOTFIX}
BRANCH_UPLOAD_DIR=${UPLOAD_DIR}/branch/${GITHUB_REF#refs/heads/}

# Skip pull request
is_pr && exit 0

# Upload templates
if is_edge; then
	aws s3 cp ${LOCAL_DIR}/${TEMPLATE_TYPE}.json s3://${S3_BUCKET}/${EDGE_UPLOAD_DIR}/${TEMPLATE_TYPE}.json --acl public-read
elif is_stable; then
	aws s3 cp ${LOCAL_DIR}/${TEMPLATE_TYPE}.json s3://${S3_BUCKET}/${STABLE_UPLOAD_DIR}/${TEMPLATE_TYPE}.json --acl public-read
elif is_release; then
	# Provide all semver version options (major, major.minor, major.minor.hotfix)
	aws s3 cp ${LOCAL_DIR}/${TEMPLATE_TYPE}.json s3://${S3_BUCKET}/${RELEASE_UPLOAD_DIR_MAJOR}/${TEMPLATE_TYPE}.json --acl public-read
	aws s3 cp ${LOCAL_DIR}/${TEMPLATE_TYPE}.json s3://${S3_BUCKET}/${RELEASE_UPLOAD_DIR_MINOR}/${TEMPLATE_TYPE}.json --acl public-read
	aws s3 cp ${LOCAL_DIR}/${TEMPLATE_TYPE}.json s3://${S3_BUCKET}/${RELEASE_UPLOAD_DIR_HOTFIX}/${TEMPLATE_TYPE}.json --acl public-read
else
	# upload templates for every branch
	aws s3 cp ${LOCAL_DIR}/${TEMPLATE_TYPE}.json s3://${S3_BUCKET}/${BRANCH_UPLOAD_DIR}/${TEMPLATE_TYPE}.json --acl public-read
fi
