# CI/CD from scratch — GitHub Actions + Terraform + AWS

Minimal, working example of a secure multi-environment CI/CD pipeline:
PR validation → build/test → push a versioned image to a private registry →
auto-deploy to **Dev** → manual approval → promote the *same* image to
**Prod**. Everything (pipeline, environments, branch protection, IAM) is
defined as code.

## Layout

```
app/                  Node.js "hello world" packaged as a Lambda container image
.github/workflows/    ci.yml (PR validation), cd.yml (main branch deploy), codeql.yml (SAST)
.github/dependabot.yml
terraform/aws/        ECR, OIDC role for GitHub Actions, Lambda (dev+prod), Secrets Manager
terraform/github/     Repo creation, branch protection, environments, RBAC
scripts/bootstrap_ecr.sh   one-time helper (see below)
```

## Why these choices ("maximally simple" but real)

- **Compute**: AWS Lambda with a container image. No cluster, load balancer,
  or VPC to manage — still genuinely "containerized infrastructure"
  (built from the same `Dockerfile`, scanned like any other image), just
  cheap and fast to stand up for two environments.
- **Registry**: a single private ECR repo, versioned images tagged with the
  git commit SHA. Dev and Prod both point at the registry; promotion means
  pointing Prod's Lambda at the tag Dev already validated — never a rebuild.
- **No stored AWS credentials**: GitHub Actions assumes an IAM role via
  OIDC (`terraform/aws/iam_oidc.tf`). The trust policy is scoped to this
  exact repo + branch/environment, so there is no access key/secret to leak
  in the first place.
- **Approval gate**: implemented with a native GitHub Environment
  (`production`), not custom pipeline logic — `terraform/github/environments.tf`
  configures required reviewers.

## Pipeline flow

**`ci.yml`** — pull requests into `main`:
1. `build-and-test`: install deps, run unit tests, build the container image, smoke-test it locally (no AWS access at all).
2. `security-scan`: `npm audit`, secret scan (gitleaks), Trivy scan of the built image. Any CRITICAL/HIGH finding fails the job.

Both jobs are required status checks on `main` (see branch protection below) — a PR cannot merge if either fails.

**`codeql.yml`** — SAST via GitHub CodeQL, on PRs, pushes to `main`, and weekly.

**`cd.yml`** — pushes to `main`:
1. `build-and-test` / `security-scan` — same gates as CI, run again against `main`.
2. `push-image` (env: `dev`) — assumes the OIDC role, builds the image, runs a final Trivy scan, pushes `":<git-sha>"` to ECR.
3. `deploy-dev` (env: `dev`) — points the Dev Lambda at that image, waits for update, invokes it as a smoke test.
4. `deploy-prod` (env: `production`) — **blocked until a required reviewer approves** the environment deployment in the GitHub UI, then points the Prod Lambda at the *exact same* image digest and smoke-tests it.

This is the Dev→Prod promotion logic: one build, one artifact, validated in Dev, promoted to Prod only after Dev succeeds and a human approves.

## Security controls (maps to acceptance criteria)

| Control | Where |
|---|---|
| No hardcoded secrets in pipeline | OIDC role assumption (`iam_oidc.tf`); no AWS keys anywhere. Real app secrets live in Secrets Manager and are read by the Lambda at runtime, never by the pipeline. |
| Least privilege for the CI/CD identity | `iam_oidc.tf` — the GitHub Actions role can only push to *this* ECR repo and update *these two* Lambda functions, nothing account-wide. |
| Least privilege at runtime | Each Lambda has its own execution role that can read only its own Secrets Manager secret (`lambda.tf`). |
| RBAC on the pipeline/repo | `terraform/github/branch_protection.tf` (`github_repository_collaborators`), GitHub Environment reviewers for `production`. |
| Branch protection | `branch_protection.tf` — required PR review, required status checks, no force-push, no deletion. |
| SAST | `codeql.yml`. |
| Dependency/vulnerability scanning | `npm audit` in `security-scan`; `vulnerability_alerts = true` + Dependabot (`.github/dependabot.yml`) for automated update PRs. |
| Secret scanning | `gitleaks` in the pipeline **and** native GitHub secret scanning + push protection enabled via `github_repository.security_and_analysis` (public repos: free). |
| Container image scanning | Trivy in both `ci.yml` and `cd.yml` (fails the pipeline on CRITICAL/HIGH), plus ECR `scan_on_push` as a second, independent check. |
| Fail on critical findings | `exit-code: '1'` on every Trivy step; `npm audit --audit-level=high` exits non-zero on findings. |
| Secure artifact storage | ECR repo policy restricts pulls/pushes to this AWS account only (`ecr.tf`); images are immutable-tagged. |
| Environment-specific config without exposing secrets | Non-sensitive values (region, function name, role ARN) are GitHub **Environment variables**; actual secrets are pulled from AWS Secrets Manager by the running Lambda, never passed through CI. |
| `.gitignore` | Repo root — excludes `.terraform/`, `*.tfstate`, `*.tfvars`, `.env*`, key files. |

## Deploying this yourself

Requires: an AWS account, a GitHub PAT (repo admin scope), Terraform >= 1.5, Docker, AWS CLI.

```bash
# 1. Create the GitHub repo with security settings baked in
cd terraform/github
export TF_VAR_github_token=...      # PAT, never commit it
terraform init
terraform apply -var github_owner=<you> -var repo_name=ci-cd-task \
                 -var 'production_reviewers=["<your-github-username>"]'

# push this local repo to the one just created, e.g.:
#   git remote add origin git@github.com:<you>/ci-cd-task.git
#   git push -u origin main

# 2. Create the AWS infra (ECR, OIDC role, Lambda, Secrets Manager)
cd ../aws
terraform init
terraform apply -var github_org=<you> -var github_repo=ci-cd-task
# Lambda needs an image to exist before it can be created:
AWS_REGION=eu-central-1 ../../scripts/bootstrap_ecr.sh
terraform apply -var github_org=<you> -var github_repo=ci-cd-task   # creates the Lambdas

# 3. Wire the two together: put terraform/aws outputs into terraform/github env vars
cd ../github
terraform apply -var github_owner=<you> -var repo_name=ci-cd-task \
  -var 'production_reviewers=["<your-github-username>"]' \
  -var aws_github_actions_role_arn=$(cd ../aws && terraform output -raw github_actions_role_arn) \
  -var ecr_repository_url=$(cd ../aws && terraform output -raw ecr_repository_url) \
  -var aws_region=eu-central-1
```

From then on: open a PR → `ci.yml` runs. Merge to `main` → `cd.yml` builds,
deploys to Dev, then waits for approval in the `production` GitHub
Environment before promoting to Prod.

## Notes / deliberate simplifications

- Terraform state is local by default (see the commented `backend "s3"` block
  in `terraform/aws/main.tf`) to keep first-run friction low; switch to a
  remote backend for anything beyond a demo.
- Only `dev` and `prod` are wired up; adding `qa` is copy/paste of one more
  entry in `local.environments` (Lambda) and one more `github_repository_environment` block.
- Secret scanning / code scanning via native GitHub features require the
  repo to be public, or GitHub Advanced Security on a private repo — either
  way, gitleaks + CodeQL + Trivy in the pipeline itself work regardless of plan.
