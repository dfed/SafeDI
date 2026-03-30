#!/bin/zsh

set -e

VERSION='2.0.0'
SAFEDI_LOCATION="$BUILD_DIR/SafeDITool-Release/$VERSION/safeditool"

# Download the tool from Github releases.
if [ -f "$SAFEDI_LOCATION" ]; then
	if [ ! -x "$SAFEDI_LOCATION" ]; then
		chmod +x "$SAFEDI_LOCATION"
	fi
else
	mkdir -p "$(dirname "$SAFEDI_LOCATION")"

	ARCH=$(uname -m)
	if [ "$ARCH" = "arm64" ]; then
		ARCH_PATH="SafeDITool-arm64"
	elif [ "$ARCH" = "x86_64" ]; then
		ARCH_PATH="SafeDITool-x86_64"
	else
		echo "Unsupported architecture: $ARCH"
		exit 1
	fi
	curl -L -o "$SAFEDI_LOCATION" "https://github.com/dfed/SafeDI/releases/download/$VERSION/$ARCH_PATH"
	chmod +x "$SAFEDI_LOCATION"
fi

# Run the tool.
SOURCE_DIR="$PROJECT_DIR/ExampleCocoaPodsIntegration"
SAFEDI_OUTPUT_DIR="$PROJECT_DIR/SafeDIOutput"
mkdir -p "$SAFEDI_OUTPUT_DIR"

# Create the manifest JSON mapping input files to output files.
# See SafeDIToolManifest in SafeDICore for the expected format.
cat > "$SAFEDI_OUTPUT_DIR/SafeDIManifest.json" << MANIFEST
{
  "dependencyTreeGeneration": {
    "$SOURCE_DIR/Views/ExampleApp.swift": "$SAFEDI_OUTPUT_DIR/ExampleApp+SafeDI.swift"
  }
}
MANIFEST

$SAFEDI_LOCATION --include "$SOURCE_DIR" --swift-manifest "$SAFEDI_OUTPUT_DIR/SafeDIManifest.json"
