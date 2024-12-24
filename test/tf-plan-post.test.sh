#! /bin/bash

test_help_message() {
	run --help

	assertEquals "Should return success" "$RETURN" 0
	assertEquals "Should not have error" "" "$ERR"
	assertContains "Should have output" "$OUT" "Post a Terraform plan to a GitHub Pull Request as a comment."
}

test_unknown_argument() {
	run --unknown

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "Unknown option"
	assertNull "Should not have output" "$OUT"
}

test_missing_repo() {
	run --no-color

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: --repo (or \$REPO) is required"
	assertNull "Should not have output" "$OUT"
}

test_missing_pr_number() {
	run --no-color --repo="owner/repo"

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: --pr-number (or \$PR_NUMBER) is required"
	assertNull "Should not have output" "$OUT"
}

test_missing_plan_text_file() {
	run --no-color --repo="owner/repo" --pr-number=1

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: Plan text file \"./plan.txt\" does not exist. If the file is in a different location, you can set it with --plan-text-file or \$PLAN_TEXT_FILE"
	assertNull "Should not have output" "$OUT"
}

test_plan_text_file_not_exists() {
	run --no-color --repo="owner/repo" --pr-number=1 --plan-text-file="./other-file.txt"

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: Plan text file \"./other-file.txt\" does not exist. If the file is in a different location, you can set it with --plan-text-file or \$PLAN_TEXT_FILE"
	assertNull "Should not have output" "$OUT"
}

test_wrong_repo() {
	run --no-color --repo="&&!" --pr-number=1 --plan-text-file="./test/terraform/success/plan.txt" --dry-run

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: Repository name '&&!' doesn't seem to be valid, it must be org/repo-name format"
	assertNull "Should not have output" "$OUT"
}

test_wrong_mode() {
	run --no-color --repo="owner/repo" --pr-number=1 --plan-text-file="./test/terraform/success/plan.txt" --mode=unknown --dry-run

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: Mode must be either 'recreate' or 'update'"
	assertNull "Should not have output" "$OUT"
}

test_no_org_in_repo() {
	run --no-color --repo="repo" --pr-number=1 --plan-text-file="./test/terraform/success/plan.txt" --dry-run

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: Repository name 'repo' doesn't seem to be valid, it must be org/repo-name format"
	assertNull "Should not have output" "$OUT"
}

test_wrong_pr_number() {
	run --no-color --repo="owner/repo" --pr-number=test --plan-text-file="./test/terraform/success/plan.txt" --dry-run

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: pr number 'test' must be an integer number"
	assertNull "Should not have output" "$OUT"
}

test_dry_run_custom_identifier_success() {
	run --no-color --repo="owner/repo" --pr-number=1 --plan-text-file="./test/terraform/success/plan.txt" --identifier="<!-- something -->" --dry-run

	EXPECTED=$(
		cat <<-"EOF"
			Auth: DRY RUN Skipping authentication
			Comment: DRY RUN Outputting comment
			> [!IMPORTANT]
			> ### Generated Terraform Plan
			> Plan: 1 to add, 0 to change, 0 to destroy.

			<details>
			<!-- something -->
			<p><summary>Terraform Plan Details</summary></p>

			```hcl
			Terraform will perform the following actions:

			  # local_file.foo will be created
			  + resource "local_file" "foo" {
			      + content              = "foo!"
			      + content_base64sha256 = (known after apply)
			      + content_base64sha512 = (known after apply)
			      + content_md5          = (known after apply)
			      + content_sha1         = (known after apply)
			      + content_sha256       = (known after apply)
			      + content_sha512       = (known after apply)
			      + directory_permission = "0777"
			      + file_permission      = "0777"
			      + filename             = "./foo.bar"
			      + id                   = (known after apply)
			    }

			Plan: 1 to add, 0 to change, 0 to destroy.
			```
			</details>
		EOF
	)

	assertEquals "Should not return error" "$RETURN" 0
	assertEquals "Should have output" "$EXPECTED" "$OUT"
	assertEquals "Should not have error" "" "$ERR"
}

test_dry_run_success() {
	run --no-color --repo="owner/repo" --pr-number=1 --plan-text-file="./test/terraform/success/plan.txt" --dry-run

	EXPECTED=$(
		cat <<-"EOF"
			Auth: DRY RUN Skipping authentication
			Comment: DRY RUN Outputting comment
			> [!IMPORTANT]
			> ### Generated Terraform Plan
			> Plan: 1 to add, 0 to change, 0 to destroy.

			<details>
			<!-- tf-plan-post.sh -->
			<p><summary>Terraform Plan Details</summary></p>

			```hcl
			Terraform will perform the following actions:

			  # local_file.foo will be created
			  + resource "local_file" "foo" {
			      + content              = "foo!"
			      + content_base64sha256 = (known after apply)
			      + content_base64sha512 = (known after apply)
			      + content_md5          = (known after apply)
			      + content_sha1         = (known after apply)
			      + content_sha256       = (known after apply)
			      + content_sha512       = (known after apply)
			      + directory_permission = "0777"
			      + file_permission      = "0777"
			      + filename             = "./foo.bar"
			      + id                   = (known after apply)
			    }

			Plan: 1 to add, 0 to change, 0 to destroy.
			```
			</details>
		EOF
	)

	assertEquals "Should not return error" "$RETURN" 0
	assertEquals "Should have output" "$EXPECTED" "$OUT"
	assertEquals "Should not have error" "" "$ERR"
}

test_dry_run_error() {
	run --no-color --repo="owner/repo" --pr-number=1 --plan-text-file="./test/terraform/error-var/plan.txt" --dry-run
	EXPECTED=$(
		cat <<-"EOF"
			Auth: DRY RUN Skipping authentication
			Comment: DRY RUN Outputting comment
			> [!CAUTION]
			> ### Generated Terraform Plan
			> Error: Reference to undeclared input variable

			<details>
			<!-- tf-plan-post.sh -->
			<p><summary>Terraform Plan Details</summary></p>

			```hcl
			Error: Reference to undeclared input variable

			  on main.tf line 2, in resource "local_file" "foo":
			   2:   content  = var.foo_content

			An input variable with the name "foo_content" has not been declared. This
			variable can be declared with a variable "foo_content" {} block.
			```
			</details>
		EOF
	)
	assertEquals "Should not return error" "$RETURN" 0
	assertEquals "Should have output" "$EXPECTED" "$OUT"
	assertEquals "Should not have error" "" "$ERR"
}

test_dry_run_no_changes() {
	run --no-color --repo="owner/repo" --pr-number=1 --plan-text-file="./test/terraform/no-changes/plan.txt" --dry-run
	EXPECTED=$(
		cat <<-"EOF"
			Auth: DRY RUN Skipping authentication
			Comment: DRY RUN Outputting comment
			> [!NOTE]
			> ### Generated Terraform Plan
			> No changes. Your infrastructure matches the configuration.

			<details>
			<!-- tf-plan-post.sh -->
			<p><summary>Terraform Plan Details</summary></p>

			```hcl

			```
			</details>
		EOF
	)
	assertEquals "Should not return error" "$RETURN" 0
	assertEquals "Should have output" "$OUT" "$EXPECTED"
	assertEquals "Should not have error" "" "$ERR"
}

test_create_comment_and_post() {
	run --no-color --repo="ivank/tf-plan-post" --pr-number=1 --plan-text-file="./test/terraform/success/plan.txt" --mode=update

	EXPECTED=$(
		cat <<-"EOF"
			Auth No explicit auth found (--token or --app-id and --installation-key), using GitHub CLI default
			Comment Searching for existing comment in PR https://github.com/ivank/tf-plan-post/pull/1
			Comment Existing comment not found, creating
			Comment Successful
		EOF
	)

	assertEquals "Should not return error" "$RETURN" 0
	assertEquals "Should have output" "$EXPECTED" "$OUT"
	assertEquals "Should not have error" "" "$ERR"

	# Check if the comment was created
	COMMENT=$(gh api "/repos/ivank/tf-plan-post/issues/1/comments" --jq '.[].body')

	EXPECTED=$(
		cat <<-"EOF"
			> [!IMPORTANT]
			> ### Generated Terraform Plan
			> Plan: 1 to add, 0 to change, 0 to destroy.

			<details>
			<!-- tf-plan-post.sh -->
			<p><summary>Terraform Plan Details</summary></p>

			```hcl
			Terraform will perform the following actions:

			  # local_file.foo will be created
			  + resource "local_file" "foo" {
			      + content              = "foo!"
			      + content_base64sha256 = (known after apply)
			      + content_base64sha512 = (known after apply)
			      + content_md5          = (known after apply)
			      + content_sha1         = (known after apply)
			      + content_sha256       = (known after apply)
			      + content_sha512       = (known after apply)
			      + directory_permission = "0777"
			      + file_permission      = "0777"
			      + filename             = "./foo.bar"
			      + id                   = (known after apply)
			    }

			Plan: 1 to add, 0 to change, 0 to destroy.
			```
			</details>
		EOF
	)

	assertEquals "Should have created comment" "$EXPECTED" "$COMMENT"
}

test_update_existing_comment_with_error_plan() {
	run --no-color --repo="ivank/tf-plan-post" --pr-number=1 --plan-text-file="./test/terraform/error/plan.txt" --mode=update

	EXPECTED=$(
		cat <<-"EOF"
			Auth No explicit auth found (--token or --app-id and --installation-key), using GitHub CLI default
			Comment Searching for existing comment in PR https://github.com/ivank/tf-plan-post/pull/1
			Comment Existing comment found
			Comment Updating existing comment
			Comment Successful
		EOF
	)

	assertEquals "Should not return error" "$RETURN" 0
	assertEquals "Should have output" "$EXPECTED" "$OUT"
	assertEquals "Should not have error" "" "$ERR"

	# Check if the last comment was updated
	COMMENT=$(gh api "/repos/ivank/tf-plan-post/issues/1/comments" --jq '.[].body')

	EXPECTED=$(
		cat <<-"EOF"
			> [!CAUTION]
			> ### Generated Terraform Plan
			> Error: Read local file data source error

			<details>
			<!-- tf-plan-post.sh -->
			<p><summary>Terraform Plan Details</summary></p>

			```hcl
			Error: Read local file data source error

			  with data.local_file.missing_file,
			  on main.tf line 1, in data "local_file" "missing_file":
			   1: data "local_file" "missing_file" {

			The file at given path cannot be read.

			+Original Error: open ./missing_file.bar: no such file or directory
			```
			</details>
		EOF
	)

	assertEquals "Should have updated the comment" "$EXPECTED" "$COMMENT"
}

test_recreate_comment() {
	run --no-color --repo="ivank/tf-plan-post" --pr-number=1 --plan-text-file="./test/terraform/error-var/plan.txt"

	EXPECTED=$(
		cat <<-"EOF"
			Auth No explicit auth found (--token or --app-id and --installation-key), using GitHub CLI default
			Comment Searching for existing comment in PR https://github.com/ivank/tf-plan-post/pull/1
			Comment Existing comment found
			Comment Deleting existing comment
			Comment Creating new comment
			Comment Successful
		EOF
	)

	assertEquals "Should not return error" "$RETURN" 0
	assertEquals "Should have output" "$EXPECTED" "$OUT"
	assertEquals "Should not have error" "" "$ERR"

	# Check if the last comment was updated
	COMMENT=$(gh api "/repos/ivank/tf-plan-post/issues/1/comments" --jq '.[].body')

	EXPECTED=$(
		cat <<-"EOF"
			> [!CAUTION]
			> ### Generated Terraform Plan
			> Error: Reference to undeclared input variable

			<details>
			<!-- tf-plan-post.sh -->
			<p><summary>Terraform Plan Details</summary></p>

			```hcl
			Error: Reference to undeclared input variable

			  on main.tf line 2, in resource "local_file" "foo":
			   2:   content  = var.foo_content

			An input variable with the name "foo_content" has not been declared. This
			variable can be declared with a variable "foo_content" {} block.
			```
			</details>
		EOF
	)

	assertEquals "Should have updated the comment" "$EXPECTED" "$COMMENT"
}

# SETUP
# --------------------------------------------

run() {
	(./tf-plan-post.sh "$@" >"$OUT_FILE" 2>"$ERR_FILE")
	RETURN=$?
	OUT=$(cat "$OUT_FILE")
	ERR=$(cat "$ERR_FILE")
}

oneTimeSetUp() {
	# Define global variables for command output.
	OUT_FILE="${SHUNIT_TMPDIR}/stdout"
	ERR_FILE="${SHUNIT_TMPDIR}/stderr"

	# Delete all the comments in the pr using gh cli
	# Get the a list of comment ids from the test pr using gh cli
	COMMENTS=$(gh api "/repos/ivank/tf-plan-post/issues/1/comments" --jq '.[].id')
	# Delete all comments from the test pr
	for comment in $COMMENTS; do
		gh api --method DELETE "/repos/ivank/tf-plan-post/issues/comments/$comment" --silent
	done
}

setUp() {
	# Truncate the output files.
	cp /dev/null "${OUT_FILE}"
	cp /dev/null "${ERR_FILE}"
}

# Load shUnit2.
. shunit2
