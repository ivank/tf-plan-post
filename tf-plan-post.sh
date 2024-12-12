#!/usr/bin/env bash

# Stop script on error
set -e

# Defaults of all variables
# We set them first, as they are used in the help message
NO_COLOR="${NO_COLOR:-}"
INSTALLATION_ID="${INSTALLATION_ID:-}"
TOKEN_SECRET_NAME="${TOKEN_SECRET_NAME:-}"
APP_ID="${APP_ID:-}"
INSTALLATION_KEY_SECRET_NAME="${INSTALLATION_KEY_SECRET_NAME:-}"
PR_NUMBER="${PR_NUMBER:-}"
REPO="${REPO:-}"
TITLE="${TITLE:-### Generated Terraform Plan}"
PLAN_TEXT_FILE="${PLAN_TEXT_FILE:-./plan.txt}"
DRY_RUN="${DRY_RUN:-false}"

# Load NO_COLOR first
# Because all the rest would use the color markers
for i in "$@"; do
	case $i in
	--no-color)
		NO_COLOR=true
		;;
	esac
done

# Set output colors (or don't use colors if NO_COLOR=true is set)
if [ -z "$NO_COLOR" ]; then
	RED='\033[0;31m'
	CYAN='\033[0;36m'
	GREEN='\033[0;32m'
	PINK='\033[0;35m'
	END='\033[0m'
else
	RED=''
	CYAN=''
	GREEN=''
	PINK=''
	END=''
fi

# Declare required commands and the steps needed to install them
declare -A REQUIRED_COMMANDS

REQUIRED_COMMANDS["berglas"]="https://github.com/GoogleCloudPlatform/berglas?tab=readme-ov-file#installation"
REQUIRED_COMMANDS["awk"]="https://learnbyexample.github.io/learn_gnuawk/installation-and-documentation.html"
REQUIRED_COMMANDS["openssl"]="https://openssl.org/"
REQUIRED_COMMANDS["jq"]="https://jqlang.github.io/jq/download/"
REQUIRED_COMMANDS["base64"]="https://www.gnu.org/software/coreutils/manual/html_node/base64-invocation.html"
REQUIRED_COMMANDS["gh"]="https://cli.github.com/"

error() {
	ERROR="
${RED}ERROR:${END} $1

Usage: ${CYAN}$(basename "$0")${END} ${PINK}--help${END}
"
	echo -e "${ERROR}" >&2
	exit 1
}

USAGE="
Usage: ${CYAN}$(basename "$0")${END} [OPTIONS]

Post a Terraform plan to a GitHub Pull Request as a comment.

You need to provide authentication credentials, either a GitHub App (recommended) or a GitHub token.
\"Secret Name\" refers to a secret in Google Secret Manager (example: sm://my-project/my-github-token).
Using [berglas](https://github.com/GoogleCloudPlatform/berglas) to access the secret.

    ${CYAN}$(basename "$0")${END} ${PINK}--token-secret-name${END}=sm://my-project/my-github-token
    ${CYAN}$(basename "$0")${END} ${PINK}--app-id${END}=1234 ${PINK}--installation-key-secret-name${END}=sm://my-project/my-installation-key

Those can also be provided as environment variables.

    ${GREEN}TOKEN_SECRET_NAME${END}=sm://my-project/my-github-token ${CYAN}$(basename "$0")${END}
    ${GREEN}APP_ID${END}=1234 ${GREEN}INSTALLATION_KEY_SECRET_NAME${END}=sm://my-project/my-installation-key ${CYAN}$(basename "$0")${END}

Additionally you need to provide the PR number, repository.
Also expects the Terraform plan text output (or error output) to be located at \"$PLAN_TEXT_FILE\".
You can override this with ${PINK}--plan-text-file${END} (or ${GREEN}\$PLAN_TEXT_FILE${END})

    ${CYAN}$(basename "$0")${END} ${PINK}--pr-number${END}=1234 ${PINK}--repo${END}=org/repo
    ${GREEN}PR_NUMBER${END}=1234 ${GREEN}REPO${END}=org/repo ${CYAN}$(basename "$0")${END}
    ${CYAN}$(basename "$0")${END} ${PINK}--pr-number${END}=1234 ${PINK}--repo${END}=org/repo ${PINK}--plan-text-file${END}=./other-plan.txt
    ${GREEN}PR_NUMBER${END}=1234 ${GREEN}REPO${END}=org/repo ${GREEN}PLAN_TEXT_FILE${END}=./other-plan.txt ${CYAN}$(basename "$0")${END}

Examples:

    ${CYAN}$(basename "$0")${END} ${PINK}--pr-number${END}=1234 ${PINK}--repo${END}=org/repo ${PINK}--token-secret-name${END}=sm://my-project/my-github-token ${PINK}--plan-text-file${END}=./other-plan.txt
    ${CYAN}$(basename "$0")${END} ${PINK}--plan${END}='-chdir=./terraform' ${PINK}--title${END}='My Terraform Plan' ${PINK}--pr-number${END}=1234 ${PINK}--repo${END}=org/repo ${PINK}--token${END}=1234
    ${CYAN}$(basename "$0")${END} ${PINK}--pr-number${END}=1234 ${PINK}--repo${END}=org/repo ${PINK}--app-id${END}=1234 ${PINK}--installation-key-secret-name${END}=sm://my-project/my-installation-key

Options:
  ${PINK}--help${END}                                 Show this message
  ${PINK}--token-secret-name${END}=value              Google secret manager name of the GitHub token (or ENV: ${GREEN}\$TOKEN_SECRET_NAME${END})
  ${PINK}${END}                                       ${RED}REQUIRED${END} Unless ${CYAN}--app-id${END} and ${CYAN}--installation-key-secret-name${END} are provided, Example: sm://my-project/my-github-token
  ${PINK}--app-id${END}=value                         Github App ID (or ENV: ${GREEN}\$APP_ID${END})
  ${PINK}${END}                                       ${RED}REQUIRED${END} if ${CYAN}--token-secret-name${END} is not provided, needs ${CYAN}--installation-key-secret-name${END}
  ${PINK}--installation-id${END}=value                Installation id, if not provided, it will be fetched from the GitHub API (or ENV: ${GREEN}\$INSTALLATION_ID${END})
  ${PINK}--installation-key-secret-name${END}=value   Installation key saved in Google Secret Manager (or ENV: ${GREEN}\$INSTALLATION_KEY_SECRET_NAME${END})
  ${PINK}${END}                                       ${RED}REQUIRED${END} if ${CYAN}--app-id${END} is provided, Example: sm://my-project/my-installation-key)
  ${PINK}--pr-number${END}=value                      ${RED}REQUIRED${END} Pull Request number (or ENV: ${GREEN}\$PR_NUMBER${END})
  ${PINK}--repo${END}=value                           ${RED}REQUIRED${END} Repository, Example: org/repo (or ENV ${GREEN}\$REPO${END})
  ${PINK}--plan-text-file${END}=value                 Terraform plan text output (or error output) (DEFAULT: \"${CYAN}$PLAN_TEXT_FILE${END}\", or ENV: ${GREEN}\$PLAN_TEXT_FILE${END})
  ${PINK}--title${END}=value                          Title for the review comment (DEFAULT: \"${CYAN}$TITLE${END}\", or ENV: ${GREEN}\$TITLE${END})
  ${PINK}--dry-run${END}                              Output the contents of the comment instead of sending it to GitHub
  ${PINK}--no-color${END}                             Disable color output (or ENV: ${GREEN}\$NO_COLOR${END})

Required commands: ${RED}${!REQUIRED_COMMANDS[*]}${END}
"

for i in "$@"; do
	case $i in
	--help)
		echo -e "$USAGE"
		exit 0
		;;
	--installation-id=*)
		INSTALLATION_ID="${i#*=}"
		shift
		;;
	--token-secret-name=*)
		TOKEN_SECRET_NAME="${i#*=}"
		shift
		;;
	--app-id=*)
		APP_ID="${i#*=}"
		shift
		;;
	--installation-key-secret-name=*)
		INSTALLATION_KEY_SECRET_NAME="${i#*=}"
		shift
		;;
	--repo=*)
		REPO="${i#*=}"
		shift
		;;
	--pr-number=*)
		PR_NUMBER="${i#*=}"
		shift
		;;
	--title=*)
		TITLE="${i#*=}"
		shift
		;;
	--plan-text-file=*)
		PLAN_TEXT_FILE="${i#*=}"
		shift
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	--no-color)
		shift
		;;
	*)
		error "Unknown option ${PINK}$i${END}"
		;;
	esac
done

# Validate required arguments
# ------------------------------------------------------------

declare -A REQUIRED_ARGS=(
	["REPO"]="--repo"
	["PR_NUMBER"]="--pr-number"
	["PLAN_TEXT_FILE"]="--plan-text-file"
)

for arg in "${!REQUIRED_ARGS[@]}"; do
	if [ -z "${!arg}" ]; then
		error "${PINK}${REQUIRED_ARGS[$arg]}${END} (or ${GREEN}\$$arg${END}) is required"
	fi
done

if [ ! -f "$PLAN_TEXT_FILE" ]; then
	error "Plan text file \"$PLAN_TEXT_FILE\" does not exist. If the file is in a different location, you can set it with ${PINK}--plan-text-file${END} or ${GREEN}\$PLAN_TEXT_FILE${END}"
fi

if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$ ]]; then
	error "Repository name '$REPO' doesn't seem to be valid, it must be org/repo-name format"
fi

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
	error "pr number '$PR_NUMBER' must be an integer number"
fi

for COMMAND in "${!REQUIRED_COMMANDS[@]}"; do
	if ! command -v "$COMMAND" &>/dev/null; then
		error "$COMMAND needs to be installed. ${REQUIRED_COMMANDS[$COMMAND]}"
	fi
done

# Authenticate
# ------------------------------------------------------------

if [ "$DRY_RUN" = true ]; then
	echo -e "${CYAN}Auth${END}: ${RED}DRY RUN${END} Skipping authentication"
else
	if [ "$TOKEN_SECRET_NAME" ]; then
		echo -e "${CYAN}Auth${END} Loading Token from Google Secret $TOKEN_SECRET_NAME"
		TOKEN=$(berglas access "$TOKEN_SECRET_NAME")
		echo -e "${CYAN}Auth${END} Token Loaded"
	else
		if [ -z "$APP_ID" ]; then
			error "${PINK}--app-id${END} (or ${GREEN}\$APP_ID${END}) is required when ${PINK}--token-secret-name${END} (or ${GREEN}\$TOKEN_SECRET_NAME${END}) is not provided"
		fi

		if [ -z "$INSTALLATION_KEY_SECRET_NAME" ]; then
			error "${PINK}--installation-key-secret-name${END} (or ${GREEN}\$INSTALLATION_KEY_SECRET_NAME${END}) is required when ${PINK}--app-id${END} (or ${GREEN}\$APP_ID${END}) is provided"
		fi

		echo -e "${CYAN}Auth${END} Loading Installation Key from Google Secret $INSTALLATION_KEY_SECRET_NAME"

		INSTALLATION_KEY=$(berglas access "$INSTALLATION_KEY_SECRET_NAME")

		# JWT
		# ======
		NOW=$(date +%s)
		IAT=$((NOW - 60))  # Issues 60 seconds in the past
		EXP=$((NOW + 600)) # Expires 10 minutes in the future

		HEADER=$(echo -n '{"typ":"JWT","alg":"RS256"}' | base64 -w 0)
		PAYLOAD=$(echo -n "{\"iat\":${IAT},\"exp\":${EXP},\"iss\":\"${APP_ID}\"}" | base64 -w 0)
		SIGNATURE=$(openssl dgst -sha256 -sign <(echo -n "$INSTALLATION_KEY") <(echo -n "$HEADER.$PAYLOAD") | base64 -w 0)
		JWT_HEADER="Authorization: Bearer $HEADER.$PAYLOAD.$SIGNATURE"

		if [ -z "$INSTALLATION_ID" ]; then
			echo -e "${CYAN}Auth${END} No Installation Id Provided, loading from GitHub API"
			INSTALLATIONS=$(curl --silent --header "$JWT_HEADER" https://api.github.com/app/installations)
			INSTALLATION_ID=$(echo "$INSTALLATIONS" | jq --raw-output "[.[] | select(.app_id == $APP_ID) | .id][0]")
			echo -e "${CYAN}Auth${END} Using $INSTALLATION_ID (for APP $APP_ID)"
		fi

		ACCESS_TOKEN=$(curl --silent --request POST --header "$JWT_HEADER" "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens")
		TOKEN=$(echo "$ACCESS_TOKEN" | jq --raw-output ".token")
	fi
	gh auth login --with-token <<<"$TOKEN"
	echo -e "${CYAN}Auth${END} Successful"
fi

# Terraform plan
# ------------------------------------------------------------

IDENTIFIER="<!-- tf-plan-post.sh -->"

SUMMARY=$(awk '/^(Error:|Plan:|Apply complete!|No changes.|Success)/ {line=$0} END {if (line) print line; else print "View output."}' "$PLAN_TEXT_FILE")

DETAILS=$(awk '/^Terraform will perform the following actions/ {flag=1} flag; /(Error:|Plan:|Apply complete!|No changes.|Success)/{flag=0}' "$PLAN_TEXT_FILE")

if [ -z "$DETAILS" ]; then
	DETAILS=$(awk '/^Error:/,0' "$PLAN_TEXT_FILE")
fi

BODY=$(
	cat <<-EOL
		$TITLE

		<details>
		$IDENTIFIER
		<p><summary>$SUMMARY</summary></p>

		\`\`\`hcl
		$DETAILS
		\`\`\`
		</details>
	EOL
)

if [ "$DRY_RUN" = true ]; then
	echo -e "${CYAN}Comment${END}: ${RED}DRY RUN${END} Outputting comment"
	echo -e "$BODY"
else
	# Create or update the comment
	# ------------------------------------------------------------
	echo -e "${CYAN}Comment${END} Searching for existing comment in PR https://github.com/$REPO/pull/$PR_NUMBER"

	set +e
	GENERATED_PLAN_COMMENT_ID=$(gh api "/repos/$REPO/issues/$PR_NUMBER/comments?per_page=100" --jq "[.[] | select(.body | contains(\"$IDENTIFIER\")) | .id][0]")
	GENERATED_PLAN_COMMENT_ID_EXIT_CODE=$?
	set -e

	if [[ "$GENERATED_PLAN_COMMENT_ID_EXIT_CODE" -eq 0 && "$GENERATED_PLAN_COMMENT_ID" ]]; then
		echo -e "${CYAN}Comment${END} Existing comment found: https://github.com/$REPO/pull/$PR_NUMBER#issuecomment-$GENERATED_PLAN_COMMENT_ID updating"
		gh api "/repos/${REPO}/issues/comments/${GENERATED_PLAN_COMMENT_ID}" --silent --method PATCH --field body="$BODY"
	else
		echo -e "${CYAN}Comment${END} Existing comment not found, Creating"
		gh api "/repos/${REPO}/issues/$PR_NUMBER/comments" --silent --method POST --field body="$BODY"
	fi

	echo -e "${CYAN}Comment${END} Successful"
fi
