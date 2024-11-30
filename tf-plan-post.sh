#!/bin/bash

# Stop script on error
set -e

# Set output colors (or don't use colors if NO_COLOR=true is set)
if [ -z "$NO_COLOR" ]; then
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  END='\033[0m'
else
  RED=''
  CYAN=''
  END=''
fi

INSTALLATION_ID="${INSTALLATION_ID:-}"
TOKEN_SECRET_NAME="${TOKEN_SECRET_NAME:-}"
APP_ID="${APP_ID:-}"
INSTALLATION_KEY_SECRET_NAME="${INSTALLATION_KEY_SECRET_NAME:-}"
PR_NUMBER="${PR_NUMBER:-}"
REPO="${REPO:-}"
TITLE="${TITLE:-### Generated Terraform Plan}"
PLAN_TEXT_FILE="${PLAN_TEXT_FILE:-./plan.txt}"

# Declare required commands and the steps needed to install them
declare -A REQUIRED_COMMANDS

REQUIRED_COMMANDS["berglas"]="https://github.com/GoogleCloudPlatform/berglas?tab=readme-ov-file#installation"
REQUIRED_COMMANDS["jwt"]="https://github.com/mike-engel/jwt-cli"
REQUIRED_COMMANDS["gh"]="https://cli.github.com/"

USAGE="
Usage: $(basename "$0") [OPTIONS]

Post a Terraform plan to a GitHub Pull Request as a comment.

You need to provide authentication credentials, either a GitHub App (recommended) or a GitHub token.
\"Secret Name\" refers to a secret in Google Secret Manager (example: sm://my-project/my-github-token). 
Using [berglas](https://github.com/GoogleCloudPlatform/berglas) to access the secret.

    $(basename "$0") --token-secret-name=sm://my-project/my-github-token
    $(basename "$0") --app-id=1234 --installation-key-secret-name=sm://my-project/my-installation-key

Those can also be provided as environment variables.

    TOKEN_SECRET_NAME=sm://my-project/my-github-token $(basename "$0")
    APP_ID=1234 INSTALLATION_KEY_SECRET_NAME=sm://my-project/my-installation-key $(basename "$0")

Additionally you need to provide the PR number, repository.
Also expects the Terraform plan text output (or error output) to be located at \"$PLAN_TEXT_FILE\").
You can override this with --plan-text-file (or \$PLAN_TEXT_FILE)

    $(basename "$0") --pr-number=1234 --repo=org/repo 
    PR_NUMBER=1234 REPO=org/repo $(basename "$0")
    $(basename "$0") --pr-number=1234 --repo=org/repo --plan-text-file=./other-plan.txt
    PR_NUMBER=1234 REPO=org/repo PLAN_TEXT_FILE=./other-plan.txt $(basename "$0")
    
Examples:

    $(basename "$0") --pr-number=1234 --repo=org/repo --token-secret-name=sm://my-project/my-github-token --plan-text-file=./other-plan.txt
    $(basename "$0") --plan='-chdir=./terraform' --title='My Terraform Plan' --pr-number=1234 --repo=org/repo --token=1234
    $(basename "$0") --pr-number=1234 --repo=org/repo --app-id=1234 --installation-key-secret-name=sm://my-project/my-installation-key

Options:
  --help                                                       Show this message
  --token-secret-name=TOKEN_SECRET_NAME                        Google secret manager name of the GitHub token
                                                               (Example: sm://my-project/my-github-token)
  --app-id=APP_ID                                              Github App ID
                                                               (REQUIRED if --token-secret-name is not provided, needs --installation-key-secret-name)
  --installation-id=INSTALLATION_ID                            Installation id, if not provided, it will be fetched from the GitHub API
  --installation-key-secret-name=INSTALLATION_KEY_SECRET_NAME  Installation key saved in Google Secret Manager
                                                               (REQUIRED if --app-id is provided, Example: sm://my-project/my-installation-key)
  --pr-number=PR_NUMBER                                        Pull Request number (REQUIRED)
  --repo=REPO                                                  Repository (REQUIRED, Example: org/repo)
  --plan-text-file=PLAN_TEXT_FILE                              Terraform plan text output (or error output) (DEFAULT: \"$PLAN_TEXT_FILE\")
  --title=TITLE                                                Title for the review comment (DEFAULT: \"$TITLE\")

Required commands: ${!REQUIRED_COMMANDS[*]}
"

for i in "$@"; do
  case $i in
  --help)
    echo -e "$USAGE"
    exit 0
    ;;
  --installation-id=*)
    INSTALLATION_ID="${i#*=}"
    shift # past argument=value
    ;;
  --token-secret-name=*)
    TOKEN_SECRET_NAME="${i#*=}"
    shift # past argument=value
    ;;
  --app-id=*)
    APP_ID="${i#*=}"
    shift # past argument=value
    ;;
  --installation-key-secret-name=*)
    INSTALLATION_KEY_SECRET_NAME="${i#*=}"
    shift # past argument=value
    ;;
  --repo=*)
    REPO="${i#*=}"
    shift # past argument=value
    ;;
  --pr-number=*)
    PR_NUMBER="${i#*=}"
    shift # past argument=value
    ;;
  --title=*)
    TITLE="${i#*=}"
    shift # past argument=value
    ;;
  --plan-text-file=*)
    PLAN_TEXT_FILE="${i#*=}"
    shift # past argument=value
    ;;
  *)
    echo "Unknown option $i"
    echo -e "$USAGE"
    exit 1
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
    echo -e "${RED}Error: ${REQUIRED_ARGS[$arg]} (or \$$arg) is required${END}"
    echo "----------------------------------------"
    echo -e "$USAGE"
    exit 1
  fi
done

if [ ! -f "$PLAN_TEXT_FILE" ]; then
  echo -e "${RED}Error: Plan text file \"$PLAN_TEXT_FILE\" does not exist${END}"
  echo "----------------------------------------"
  echo -e "$USAGE"
  exit 1
fi

for COMMAND in "${!REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$COMMAND" &>/dev/null; then
    echo -e "${RED}Error: $COMMAND needs to be installed. ${REQUIRED_COMMANDS[$COMMAND]}${END}"
    exit 1
  fi
done

# Authenticate
# ------------------------------------------------------------

if [ "$TOKEN_SECRET_NAME" ]; then
  echo -e "${CYAN}Auth${END} Loading Token from Google Secret $TOKEN_SECRET_NAME"
  TOKEN=$(berglas access "$TOKEN_SECRET_NAME")
  echo -e "${CYAN}Auth${END} Token Loaded"
else
  if [ -z "$APP_ID" ]; then
    echo -e "${RED}Error: --app-id (or \$APP_ID) is required when --token-secret-name (or \$TOKEN_SECRET_NAME) is not provided${END}"
    echo -e "$USAGE"
    exit 1
  fi

  echo -e "${CYAN}Auth${END} Loading Installation Key from Google Secret $INSTALLATION_KEY_SECRET_NAME"

  INSTALLATION_KEY=$(berglas access "$INSTALLATION_KEY_SECRET_NAME")
  INSTALLATION_KEY_PATH="$(mktemp --suffix .pem)"
  trap 'rm $INSTALLATION_KEY_PATH' EXIT
  echo "$INSTALLATION_KEY" >"$INSTALLATION_KEY_PATH"

  JWT=$(jwt encode --secret "@${INSTALLATION_KEY_PATH}" --iss "${APP_ID}" -e "10 minutes" --alg RS256)
  AUTH_HEADER="Authorization: Bearer $JWT"

  if [ -z "$INSTALLATION_ID" ]; then
    echo -e "${CYAN}Auth${END} No Installation Id Provided, loading from GitHub API"
    INSTALLATION_ID=$(gh api "/app/installations" --header "$AUTH_HEADER" --jq "[.[] | select(.app_id == $APP_ID) | .id][0]")
  fi

  TOKEN=$(gh api "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" --method POST --header "$AUTH_HEADER" --jq ".token")
  echo -e "${CYAN}Auth${END} Token Loaded"
fi

gh auth login --with-token <<<"$TOKEN"
echo -e "${CYAN}Auth${END} Successful"

# Terraform plan
# ------------------------------------------------------------

SUMMARY=$(awk '/^(Error:|Plan:|Apply complete!|No changes.|Success)/ {line=$0} END {if (line) print line; else print "View output."}' "$PLAN_TEXT_FILE")

DETAILS=$(awk '/^Terraform will perform the following actions/ {flag=1} flag; /(Error:|Plan:|Apply complete!|No changes.|Success)/{flag=0}' "$PLAN_TEXT_FILE")

BODY="$TITLE

<details>
<p><summary>$SUMMARY</summary></p>

\`\`\`hcl
$DETAILS
\`\`\`
</details>"

# Create or update the comment
# ------------------------------------------------------------
echo -e "${CYAN}Comment${END} Searching for existing comment in PR https://github.com/$REPO/pull/$PR_NUMBER"

GENERATED_PLAN_COMMENT_ID=$(gh api "/repos/$REPO/issues/$PR_NUMBER/comments?per_page=100" --jq "[.[] | select(.body | startswith(\"$TITLE\")) | .id][0]" || true)

if [ "$GENERATED_PLAN_COMMENT_ID" ]; then
  echo -e "${CYAN}Comment${END} Comment found: https://github.com/$REPO/pull/$PR_NUMBER#issuecomment-$GENERATED_PLAN_COMMENT_ID"
  gh api "/repos/${REPO}/issues/comments/${GENERATED_PLAN_COMMENT_ID}" --silent --method PATCH --field body="$BODY"
else
  echo -e "${CYAN}Comment${END} Creating"
  gh api "/repos/${REPO}/issues/$PR_NUMBER/comments" --silent --method POST --field body="$BODY"
fi

echo -e "${CYAN}Comment${END} Successful"
