Pod::Spec.new do |s|
  s.name     = 'SafeDI'
  s.version  = '1.4.2'
  s.summary  = 'Compile-time-safe dependency injection'
  s.homepage = 'https://github.com/dfed/SafeDI'
  s.license  = 'MIT'
  s.authors  = 'Dan Federman'
  s.source   = { :git => 'https://github.com/dfed/SafeDI.git', :tag => s.version }

  s.ios.deployment_target = '13.0'
  s.tvos.deployment_target = '13.0'
  s.watchos.deployment_target = '6.0'
  s.macos.deployment_target = '10.15'
  s.visionos.deployment_target = '1.0'

  s.source_files = 'Sources/SafeDI/**/*.{swift}'
  s.preserve_paths = 'Package.swift', 'Sources/**/*', 'Tests/**/*', 'Plugins/**/*'

  # The below scripts and flags were inspired by https://soumyamahunt.medium.com/support-swift-macros-with-cocoapods-3911f9317042
  script = <<-SCRIPT.squish
  env -i PATH="$PATH" "$SHELL" -l -c
  "set -x; SAFEDI_MACRO_COCOAPODS_BUILD=1 swift build -c $(echo ${CONFIGURATION} | tr '[:upper:]' '[:lower:]') --product SafeDIMacros
  --sdk \\"`xcrun --show-sdk-path`\\"
  --package-path \\"${PODS_TARGET_SRCROOT}\\"
  --scratch-path \\"${PODS_BUILD_DIR}/Macros/SafeDIMacros\\""
  SCRIPT

  s.script_phase = {
    :name => 'Build SafeDI macro plugin',
    :script => script,
    :input_files => Dir.glob("{Package.swift,Sources/SafeDIMacros/**/*,Sources/SafeDICore/**/*").map {
      |path| "$(PODS_TARGET_SRCROOT)/#{path}"
    },
    :output_files => ["$(PODS_BUILD_DIR)/Macros/SafeDIMacros/${CONFIGURATION}/SafeDIMacros-tool"],
    :execution_position => :before_compile
  }

  xcconfig = {
    'OTHER_SWIFT_FLAGS' => "-Xfrontend -load-plugin-executable -Xfrontend ${PODS_BUILD_DIR}/Macros/SafeDIMacros/${CONFIGURATION}/SafeDIMacros-tool#SafeDIMacros",
  }
  s.user_target_xcconfig = xcconfig
  s.pod_target_xcconfig = xcconfig
end
