#!/bin/zsh -l

set -e

ROOT="$(git rev-parse --show-toplevel)"
BUILD_DIR="${ROOT}/.build"
SCHEME="SafeDI"
CONFIGURATION="Release"

xcrun swift build -c release \
  --product SafeDIMacros \
  --sdk $(xcrun --show-sdk-path)

PLUGIN_PATH="${BUILD_DIR}/release/SafeDIMacros-tool"
if [ ! -f "${PLUGIN_PATH}" ]; then
  echo "ERROR: Macro plugin not found at: ${PLUGIN_PATH}"
  exit 1
fi
echo "Found macro plugin at: ${PLUGIN_PATH}"

echo "Archiving for iOS (device)…"
xcrun xcodebuild archive \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=iOS" \
  -archivePath "${BUILD_DIR}/${SCHEME}-iOS" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  OTHER_SWIFT_FLAGS="-Xfrontend -load-plugin-executable -Xfrontend $PLUGIN_PATH#SafeDIMacros"

echo "Archiving for iOS (simulator)…"
xcrun xcodebuild archive \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "${BUILD_DIR}/${SCHEME}-iOS-Sim" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES
  OTHER_SWIFT_FLAGS="-Xfrontend -load-plugin-executable -Xfrontend $PLUGIN_PATH#SafeDIMacros"

echo "Creating the XCFramework…"
xcrun xcodebuild -create-xcframework \
  -framework "${BUILD_DIR}/${SCHEME}-iOS.xcarchive/Products/Library/Frameworks/${SCHEME}.framework" \
  -framework "${BUILD_DIR}/${SCHEME}-iOS-Sim.xcarchive/Products/Library/Frameworks/${SCHEME}.framework" \
  -output "${BUILD_DIR}/${SCHEME}.xcframework"

echo "XCFramework is located at:\n\t ${BUILD_DIR}/${SCHEME}.xcframework"
