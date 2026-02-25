#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftAWSLambdaRuntime open source project
##
## Copyright (c) 2017-2024 Apple Inc. and the SwiftAWSLambdaRuntime project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

EXAMPLE=HelloWorldNoTraits
OUTPUT_DIR=.build/release
OUTPUT_FILE=${OUTPUT_DIR}/MyLambda
LIBS_TO_CHECK="libFoundation.so libFoundationInternationalization.so lib_FoundationICU.so"

pushd Examples/${EXAMPLE} > /dev/null || fatal "Failed to change directory to Examples/${EXAMPLE}."

# recompile the example without the --static-swift-stdlib flag
swift build -c release || fatal "Failed to build the example."

# check if the binary exists
if [ ! -f "${OUTPUT_FILE}" ]; then
  fatal "❌ ${OUTPUT_FILE} does not exist."
fi

# Checking for Foundation or ICU dependencies
echo "Checking for Foundation or ICU dependencies in ${OUTPUT_FILE}."
LIBRARIES=$(ldd ${OUTPUT_FILE} | awk '{print $1}')
for LIB in ${LIBS_TO_CHECK}; do
  echo -n "Checking for ${LIB}... "
  
  # check if the binary has a dependency on Foundation or ICU
  # grep -q suppresses output; returns 0 if found, 1 if not found
  echo "${LIBRARIES}" | grep -q "${LIB}"
  FOUND=$?
  if [ "$FOUND" -eq 0 ]; then
    log "❌ ${LIB} found." && break
  else
    log "✅ ${LIB} not found."
  fi
done

popd > /dev/null || fatal "Failed to change directory back to the root directory."

# FOUND is 0 if grep matched (lib was found), 1 if not
if [ "$FOUND" -eq 0 ]; then
  fatal "❌ At least one foundation lib was found, reporting the error."
else
  log "✅ No foundation lib found, congrats!" && exit 0
fi