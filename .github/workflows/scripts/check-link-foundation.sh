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

EXAMPLE=APIGateway
OUTPUT_DIR=.build/release
OUTPUT_FILE=${OUTPUT_DIR}/APIGatewayLambda
LIBS_TO_CHECK="libFoundation.so libFoundationInternationalization.so lib_FoundationICU.so"

pushd Examples/${EXAMPLE} || fatal "Failed to change directory to Examples/${EXAMPLE}."

# recompile the example without the --static-swift-stdlib flag
LAMBDA_USE_LOCAL_DEPS=../.. swift build -c release -Xlinker -s || fatal "Failed to build the example."

# check if the binary exists
if [ ! -f "${OUTPUT_FILE}" ]; then
  error "❌ ${OUTPUT_FILE} does not exist."
fi

# Checking for Foundation or ICU dependencies
echo "Checking for Foundation or ICU dependencies in ${OUTPUT_DIR}/${OUTPUT_FILE}."
LIBRARIES=$(ldd ${OUTPUT_FILE} | awk '{print $1}')
for LIB in ${LIBS_TO_CHECK}; do
  echo -n "Checking for ${LIB}... "
  
  # check if the binary has a dependency on Foundation or ICU
  echo "${LIBRARIES}" | grep "${LIB}"  # return 1 if not found

  # 1 is success (grep failed to find the lib), 0 is failure (grep successly found the lib)
  SUCCESS=$?
  [ "$SUCCESS" -eq 0 ] && log "❌ ${LIB} found." && break || log "✅ ${LIB} not found."
done

popd || fatal "Failed to change directory back to the root directory."

# exit code is the opposite of the grep exit code
[ "$SUCCESS" -eq 0 ] && error "❌ At least one foundation lib was found, reporting the error." || log "✅ No foundation lib found, congrats!" && exit 0