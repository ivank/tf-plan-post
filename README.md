# Terraform Plan Post

A dockerized bash script that posts Terraform plan output to a GitHub Pull Request as a comment.
Suitable for use in Google Cloud Build.

## Usage

```yaml
steps:
  - id: Run
    name: hashicorp/terraform:1.8.2
    script: |
      set -ex
      terraform init -no-color
      terraform plan -no-color > >(tee plan.txt)

  - id: Post
    name: ghcr.io/ivank/tf-plan-post:1.0.0
    env:
      - APP_ID=123
      - INSTALLATION_KEY=sm://my-project/my-installation-key
      - REPO=$REPO_FULL_NAME
      - PR_NUMBER=$_PR_NUMBER
```

`tf-plan-post.sh` can also capture and process failed plans. This does required a little bit more boilerplate from cloud build, since it doesn't support failing steps natively.

```yaml
steps:
  - id: Plan
    name: hashicorp/terraform:1.8.2
    script: |
      set -ex
      terraform init -no-color 
      terraform plan -no-color 2> >(tee plan.txt) > >(tee plan.txt) || touch plan-failed.txt

  - id: Post
    name: ghcr.io/ivank/tf-plan-post:1.0.0
    env:
      - TOKEN=sm://$PROJECT_ID/test-github-token
      - REPO=$REPO_FULL_NAME
      - PR_NUMBER=$_PR_NUMBER

  - id: Plan result
    name: hashicorp/terraform:1.8.2
    script: |
      set -ex
      if [ -f plan-failed.txt ]; then
        exit 1
      fi
```

### Secrets

The script uses [berglas](https://github.com/GoogleCloudPlatform/berglas) to be able to load secrets from google secret manager directly. Secrets that start with "sm://" are piped through berglas.

```console
--token=sm://my-project/my-secret-name
# or
TOKEN=sm://my-project/my-secret-name
```

But if you don't use it you can just directly provide the secret value too.(or specify the corresponding environment variables).

```console
--token=$GH_TOKEN
# or
TOKEN=$GH_TOKEN
```

## Documentation

You can run `./tf-plan-post.sh --help` to get the usage docs:

![Help](docs/help.svg)

## Development

To run the tests you need [shunit2](https://github.com/kward/shunit2) installed.

```console
brew install shunit2
```

Running the tests

```console
test/tf-plan-post.test.sh
```

To rebuild the docs/help.svg file you will need [ansisvg](https://github.com/wader/ansisvg)

```console
./tf-plan-post.sh --help | ansisvg --colorscheme 'Apple System Colors' --charboxsize 9x16 --marginsize=4x4 > docs/help.svg
```

## Deployment

Github Releases deploys a new version to github packages
