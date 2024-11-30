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
      terraform plan -no-color 2> >(tee plan.txt) > >(tee plan.txt)

  - id: Post
    name: ghcr.io/ivank/tf-plan-post:0.0.10
    env:
      - APP_ID=123
      - INSTALLATION_KEY_SECRET_NAME=sm://my-project/my-installation-key
      - REPO=$REPO_FULL_NAME
      - PR_NUMBER=$_PR_NUMBER
```
