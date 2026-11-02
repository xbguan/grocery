#!/bin/zsh
set -eu
cd "${0:A:h}/.."
t=$(mktemp -d /private/tmp/grocery-store-XXXXXX)
trap 'rm -rf "$t"' EXIT
sources=(Sources/OpenAIBar/{Config,KeyStore}.swift Tests/KeyStoreTests.swift)
swiftc -module-cache-path .build/test-module-cache "${sources[@]}" -o "$t/A"
swiftc -O -module-cache-path .build/test-module-cache "${sources[@]}" -o "$t/B"
CREDENTIAL_TEST_HOME="$t" "$t/A" seed
CREDENTIAL_TEST_HOME="$t" "$t/B" upgrade
