#! /bin/sh

test_help_message() {
	run --help

	assertEquals "Should return success" "$RETURN" 0
	assertNull "Should not have error" "$ERR"
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

test_missing_token() {
	run --no-color --repo="owner/repo" --pr-number=1 --plan-text-file="./test/terraform/success/plan.txt"

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: --app-id (or \$APP_ID) is required when --token-secret-name (or \$TOKEN_SECRET_NAME)"
	assertNull "Should not have output" "$OUT"
}

test_missing_installation_key() {
	run --no-color --repo="owner/repo" --pr-number=1 --plan-text-file="./test/terraform/success/plan.txt" --app-id=1

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: --installation-key-secret-name (or \$INSTALLATION_KEY_SECRET_NAME) is required when --app-id (or \$APP_ID) is provided"
	assertNull "Should not have output" "$OUT"
}

test_wrong_repo() {
	run --no-color --repo="&&!" --pr-number=1 --plan-text-file="./test/terraform/success/plan.txt" --token-secret-name="..." --dry-run

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: Repository name '&&!' doesn't seem to be valid, it must be org/repo-name format"
	assertNull "Should not have output" "$OUT"
}

test_no_org_in_repo() {
	run --no-color --repo="repo" --pr-number=1 --plan-text-file="./test/terraform/success/plan.txt" --token-secret-name="..." --dry-run

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: Repository name 'repo' doesn't seem to be valid, it must be org/repo-name format"
	assertNull "Should not have output" "$OUT"
}

test_wrong_pr_number() {
	run --no-color --repo="owner/repo" --pr-number=test --plan-text-file="./test/terraform/success/plan.txt" --token-secret-name="..." --dry-run

	assertEquals "Should return error" "$RETURN" 1
	assertContains "Should have error" "$ERR" "ERROR: pr number 'test' must be an integer number"
	assertNull "Should not have output" "$OUT"
}

test_dry_run_success() {
	run --no-color --repo="owner/repo" --pr-number=1 --plan-text-file="./test/terraform/success/plan.txt" --token-secret-name="..." --dry-run

	EXPECTED=$(
		cat <<-"EOF"
			Auth: DRY RUN Skipping authentication
			Comment: DRY RUN Outputting comment
			### Generated Terraform Plan

			<details>
			<!-- tf-plan-post.sh -->
			<p><summary>Plan: 1 to add, 0 to change, 0 to destroy.</summary></p>

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
	assertEquals "Should have output" "$OUT" "$EXPECTED"
	assertNull "Should not have error" "$ERR"
}

test_dry_run_error() {
	run --no-color --repo="owner/repo" --pr-number=1 --plan-text-file="./test/terraform/error-var/plan.txt" --token-secret-name="..." --dry-run
	EXPECTED=$(
		cat <<-"EOF"
			Auth: DRY RUN Skipping authentication
			Comment: DRY RUN Outputting comment
			### Generated Terraform Plan

			<details>
			<!-- tf-plan-post.sh -->
			<p><summary>Error: Reference to undeclared input variable</summary></p>

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
	assertEquals "Should have output" "$OUT" "$EXPECTED"
	assertNull "Should not have error" "$ERR"
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
}

setUp() {
	# Truncate the output files.
	cp /dev/null "${OUT_FILE}"
	cp /dev/null "${ERR_FILE}"
}

# Load shUnit2.
. shunit2
