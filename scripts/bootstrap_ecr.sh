#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?set AWS_REGION}"
REPO_URL=$(cd "$(dirname "$0")/../terraform/aws" && terraform output -raw ecr_repository_url)
ACCOUNT_ID=$(echo "$REPO_URL" | cut -d. -f1)

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

for ENV in dev prod; do
  docker build -t "$REPO_URL:${ENV}-bootstrap" ../app
  docker push "$REPO_URL:${ENV}-bootstrap"
done

echo "Bootstrap images pushed. You can now run 'terraform apply' for the Lambda functions."
