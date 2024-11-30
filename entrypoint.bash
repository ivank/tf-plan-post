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

INSTALLATION_ID=""
TOKEN_SECRET_NAME=""
APP_ID=""
INSTALLATION_KEY_SECRET_NAME=""
PR_NUMBER=""
REPO=""
TITLE="### Generated Terraform Plan"
PLAN_TEXT=""

# Declare required commands and the steps needed to install them
declare -A REQUIRED_COMMANDS

REQUIRED_COMMANDS["berglas"]="https://github.com/GoogleCloudPlatform/berglas?tab=readme-ov-file#installation"
REQUIRED_COMMANDS["jwt"]="https://github.com/mike-engel/jwt-cli"
REQUIRED_COMMANDS["gh"]="https://cli.github.com/"

USAGE="
Usage: $(basename "$0")

Authenticate gh cli with a GitHub App, or provide a token directly

Examples:

    $(basename "$0") --pr-number=1234 --repo=org/repo --token-secret-name=sm://my-project/my-github-token
    $(basename "$0") --plan='-chdir=./terraform' --title='My Terraform Plan' --pr-number=1234 --repo=org/repo --token=1234
    $(basename "$0") --pr-number=1234 --repo=org/repo --app-id=1234 --installation-key-secret-name=sm://my-project/my-installation-key

Options:
  --help ${CYAN}${END}                                                      Show this message
  --token-secret-name=${CYAN}TOKEN_SECRET_NAME${END}                        Google secret manager name of the GitHub token 
                                                                            (Example: sm://my-project/my-github-token)
  --app-id=${CYAN}APP_ID${END}                                              Github App ID 
                                                                            (REQUIRED if --token-secret-name is not provided, needs --installation-key-secret-name)
  --installation-id=${CYAN}INSTALLATION_ID${END}                            Installation id, if not provided, it will be fetched from the GitHub API
  --installation-key-secret-name=${CYAN}INSTALLATION_KEY_SECRET_NAME${END}  Installation key saved in Google Secret Manager 
                                                                            (REQUIRED if --app-id is provided, Example: sm://my-project/my-installation-key)
  --pr-number=${CYAN}PR_NUMBER${END}                                        Pull Request number (REQUIRED)
  --repo=${CYAN}REPO${END}                                                  Repository (REQUIRED, Example: org/repo)
  --plan-text=${CYAN}PLAN${END}                                             Terraform plan text output (or error output) 
  --title=${CYAN}TITLE${END}                                                Title for the review comment (DEFAULT: $TITLE)

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
  --plan-text=*)
    PLAN_TEXT="${i#*=}"
    shift # past argument=value
    ;;
  *)
    echo "Unknown option $i"
    echo -e "$USAGE"
    exit 1
    ;;
  esac
done

declare -A REQUIRED_ARGS=(
  ["REPO"]="--repo"
  ["PR_NUMBER"]="--pr-number"
  ["PLAN_TEXT"]="--plan-text"
)

for arg in "${!REQUIRED_ARGS[@]}"; do
  if [ -z "${!arg}" ]; then
    echo -e "${RED}Error: ${REQUIRED_ARGS[$arg]} is required${END}"
    echo -e "$USAGE"
    exit 1
  fi
done

# Require commands
# ------------------------------------------------------------

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
    echo -e "${RED}Error: --app-id is required when --token-secret-name is not provided${END}"
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

SUMMARY=$(awk '/^(Error:|Plan:|Apply complete!|No changes.|Success)/ {line=$0} END {if (line) print line; else print "View output."}' "$PLAN_TEXT")

DETAILS=$(awk '/^Terraform will perform the following actions/ {flag=1} flag; /(Error:|Plan:|Apply complete!|No changes.|Success)/{flag=0}' "$PLAN_TEXT")

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
