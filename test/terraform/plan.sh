#!/bin/bash

# Loop through each directory in the current directory
for dir in */; do
	if [ -d "$dir" ]; then
		cd "$dir" || exit
		echo "Processing directory: $dir"

		# Run terraform init
		terraform init

		# Run terraform plan and output to plan.txt
		terraform plan -no-color >plan.txt 2>&1

		# Return to the parent directory
		cd ..
	fi
done
