#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftAWSLambdaRuntime open source project
##
## Copyright SwiftAWSLambdaRuntime project authors
## Copyright (c) Amazon.com, Inc. or its affiliates.
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

export HOST=127.0.0.1
export PORT=7777
export AWS_LAMBDA_RUNTIME_API="$HOST:$PORT"
export LOG_LEVEL=error # important, otherwise log becomes a bottleneck

DATE_CMD="date"
# using gdate on darwin for nanoseconds
# gdate is installed by coreutils on macOS
if [[ $(uname -s) == "Darwin" ]]; then
  if ! command -v gdate &> /dev/null; then
    # shellcheck disable=SC2006 # we explicitly want to use backticks here
    fatal "gdate could not be found. Please \`brew install coreutils\` to proceed."
  fi
  DATE_CMD="gdate"
fi
echo "⏱️ using $DATE_CMD to count time"

if ! command -v "$DATE_CMD" &> /dev/null; then
  fatal "$DATE_CMD could not be found. Please install $DATE_CMD to proceed."
fi

echo "🏗️ Building library and test functions"
swift build -c release -Xswiftc -g
swift build --package-path Examples/HelloWorld -c release -Xswiftc -g
swift build --package-path Examples/HelloJSON -c release -Xswiftc -g

cleanup() {
  pkill -9 MockServer && echo "killed previous mock server" # ignore-unacceptable-language
}

# start a mock server
start_mockserver() {
    if [ $# -ne 2 ]; then
        fatal "Usage: $0 <mode> <invocations>"
    fi
    MODE=$1
    INVOCATIONS=$2
    pkill -9 MockServer && echo "killed previous mock server" && sleep 1 # ignore-unacceptable-language
    echo "👨‍🔧 starting server in $MODE mode for $INVOCATIONS invocations"
    (MAX_INVOCATIONS="$INVOCATIONS" MODE="$MODE" ./.build/release/MockServer) &
    server_pid=$!
    sleep 1
    kill -0 $server_pid # check server is alive # ignore-unacceptable-language
}

cold_iterations=100
warm_iterations=1000
results=()

#------------------
# string
#------------------

MODE=string

# Start mock server
start_mockserver "$MODE" "$cold_iterations"

# cold start
echo "🚀❄️ running $MODE mode $cold_iterations cold test"
cold=()
for (( i=0; i<cold_iterations; i++ )); do
  start=$("$DATE_CMD" +%s%N)
  ./Examples/HelloWorld/.build/release/MyLambda
  end=$("$DATE_CMD" +%s%N)
  cold+=( $((end-start)) )
done
sum_cold=$(IFS=+; echo "$((${cold[*]}))")
avg_cold=$((sum_cold/cold_iterations))
results+=( "$MODE, cold: $avg_cold (ns)" )

# reset mock server 
start_mockserver "$MODE" "$warm_iterations"

# normal calls
echo "🚀🌤️ running $MODE mode warm test"
start=$("$DATE_CMD" +%s%N)
./Examples/HelloWorld/.build/release/MyLambda
end=$("$DATE_CMD" +%s%N)
sum_warm=$((end-start-avg_cold)) # substract by avg cold since the first call is cold
avg_warm=$((sum_warm/(warm_iterations-1))) # substract since the first call is cold
results+=( "$MODE, warm: $avg_warm (ns)" )

#------------------
# JSON
#------------------

export MODE=json

# Start mock server
start_mockserver "$MODE" "$cold_iterations"

# cold start
echo "🚀❄️ running $MODE mode cold test"
cold=()
for (( i=0; i<cold_iterations; i++ )); do
  start=$("$DATE_CMD" +%s%N)
  ./Examples/HelloJSON/.build/release/HelloJSON
  end=$("$DATE_CMD" +%s%N)
  cold+=( $((end-start)) )
done
sum_cold=$(IFS=+; echo "$((${cold[*]}))")
avg_cold=$((sum_cold/cold_iterations))
results+=( "$MODE, cold: $avg_cold (ns)" )

# reset mock server 
start_mockserver "$MODE" "$warm_iterations"

# normal calls
echo "🚀🌤️ running $MODE mode warm test"
start=$("$DATE_CMD" +%s%N)
./Examples/HelloJSON/.build/release/HelloJSON
end=$("$DATE_CMD" +%s%N)
sum_warm=$((end-start-avg_cold)) # substract by avg cold since the first call is cold
avg_warm=$((sum_warm/(warm_iterations-1))) # substract since the first call is cold
results+=( "$MODE, warm: $avg_warm (ns)" )

# print results
echo "-----------------------------"
echo "results"
echo "-----------------------------"
for i in "${results[@]}"; do
   echo "$i"
done
echo "-----------------------------"

# cleanup
cleanup
