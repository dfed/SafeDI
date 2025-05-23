#!/bin/zsh -l
set -e

function exportlcov() {
	executable_name=$1

	executable=$(find .build/*/*/$executable_name.xctest/Contents/*/$executable_name -type f)
	profile=$(find .build -type f -name 'default.profdata')
	output_file_name="$executable_name.lcov"

	can_proceed=true
	if [[ -z $profile ]]; then
		echo "\tAborting creation of $output_file_name – no profile found."
	elif [[ -z $executable ]]; then
		echo "\tAborting creation of $output_file_name – no executable found."
	else
		output_dir=".build/artifacts/$build_type"
		mkdir -p $output_dir

		output_file="$output_dir/$output_file_name"
		echo "\tExporting $output_file"
		xcrun llvm-cov export -format="lcov" $executable -instr-profile $profile >$output_file
	fi
}

exportlcov 'SafeDIPackageTests'
