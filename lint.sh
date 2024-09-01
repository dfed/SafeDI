#!/bin/zsh

set -e

pushd $(git rev-parse --show-toplevel)

swift run --package-path CLI -c release swiftformat --swiftversion 5.10 .

popd

