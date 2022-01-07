#!/usr/bin/env bash

# Created by Steven Barre of Advanced Solutions
# Will print out info on the size of all image streams in a namespace to assist
# in cleaing up the image registry

# Turn on bash's job control monitoring
set -o monitor
# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
#set -o xtrace

# Print a backtrace on error
# https://github.com/ab/bin/blob/master/bash-backtrace.sh
bash_backtrace() {
    # Return value of command that caused error
    local RET=$?
    # Frame counter
    local I=0
    # backtrace layers
    local FRAMES=${#BASH_SOURCE[@]}

    # Restore STDOUT and STDERR as they might be in unknown states due to catching
    # an error in the middle of a command
    exec 1>&3 2>&4

    error "Traceback (most recent call last):"

    for ((FRAME=FRAMES-2; FRAME >= 0; FRAME--)); do
        local LINENO=${BASH_LINENO[FRAME]}

        # Location of error
        error "  File ${BASH_SOURCE[FRAME+1]}, line ${LINENO}, in ${FUNCNAME[FRAME+1]}"

        # Print the error line, with preceding whitespace removed
        error "$(sed -n "${LINENO}s/^[   ]*/    /p" "${BASH_SOURCE[FRAME+1]}")"
    done

    error "Exiting with status ${RET}"
    exit "${RET}"
}

# Copy STDOUT and STDERR so they can be restored later
exec 3>&1 4>&2
# Trap script errors and print some helpful debug info
trap bash_backtrace ERR

# Check for passed in namespace
if [[ -z "${1:-}" ]]
then
  echo "Please specify a namespace"
  exit 1
fi

NS="${1}"

# Check that needed tools exist
OC=$(which oc 2>/dev/null ||true)
if [[ -z "${OC}" ]]
then
  echo "oc is not installed or in the path"
  exit 1
fi
JQ=$(which jq 2>/dev/null ||true)
if [[ -z "${JQ}" ]]
then
  echo "jq is not installed or in the path"
  exit 1
fi
NUMFMT=$(which numfmt 2>/dev/null ||true)
if [[ -z "${NUMFMT}" ]]
then
  echo "numfmt is not installed or in the path"
  exit 1
fi

# Get list of image streams for this namespace
IMAGESTREAMS=$(oc -n ${NS} get ImageStreams -o=custom-columns=NAME:.metadata.name --no-headers)

# Initialize a total size accumulator
TOTALSIZE=0

# Loop through the ImageStreams
for IMAGESTREAM in ${IMAGESTREAMS}
do
  # Initialize a size accumulator for this ImageStream
  IMAGESIZE=0
  echo "${IMAGESTREAM}:"
  # Get the raw json of the ImageStream
  ISJSON=$(oc get --raw=/apis/image.openshift.io/v1/namespaces/${NS}/imagestreams/${IMAGESTREAM})
  # Parse out the list of tags
  TAGS=$(echo "${ISJSON}" | jq -r '.status.tags[]?.tag')
  # Loop through the ImageStreamTags
  for TAG in ${TAGS}
  do
    # Initialize a size accumulator for this ImageStreamTag
    TAGSIZE=0
    # If the image has no tags, break out
    [[ -z "${TAG}" ]] && break
    echo "  ${TAG}:"
    # Parse out the image SHAs in this tag stream
    # Each push to a tag will upload a new SHA
    # The image pruner will keep the most recent 4 days or 3 SHAs
    IMAGES=$(echo "${ISJSON}" | jq -r '.status.tags[]|select(.tag == "'"${TAG}"'")|.items[]|.image')
    # Loop through the SHAs
    for IMAGE in ${IMAGES}
    do
      # Get the size in bytes of the SHA
      SIZE=$(oc get --raw="/apis/image.openshift.io/v1/namespaces/${NS}/imagestreamimages/${IMAGESTREAM}@${IMAGE}" | jq -r '.image.dockerImageMetadata.Size')
      # Add to the accumulators
      TAGSIZE=$(( $TAGSIZE + $SIZE ))
      IMAGESIZE=$(( $IMAGESIZE + $SIZE ))
      TOTALSIZE=$(( $TOTALSIZE + $SIZE ))
      # Format and print
      SIZEFMT=$(numfmt --to=iec-i --suffix=B ${SIZE})
      echo "    ${IMAGE}: ${SIZEFMT}"
    done
    TAGSIZEFMT=$(numfmt --to=iec-i --suffix=B ${TAGSIZE})
    echo  "    Tag Total: ${TAGSIZEFMT}"
  done
  IMAGESIZEFMT=$(numfmt --to=iec-i --suffix=B ${IMAGESIZE})
  echo "  Image Total: ${IMAGESIZEFMT}"
done
TOTALSIZEFMT=$(numfmt --to=iec-i --suffix=B ${TOTALSIZE})
echo "======================="
echo "Namespace Total: ${TOTALSIZEFMT}"
