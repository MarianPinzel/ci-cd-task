# CI/CD from scratch — GitHub Actions + Terraform + AWS

Minimal, working example of a secure multi-environment CI/CD pipeline:
PR validation → build/test → push a versioned image to a private registry →
auto-deploy to **Dev** → manual approval → promote the *same* image to
**Prod**. Everything (pipeline, environments, branch protection, IAM) is
defined as code.

## Layout

```
app/                  Node.js "hello world" HTTP server, packaged as a container image
.github/workflows/    ci.yml (PR validation), cd.yml (main branch deploy), codeql.yml (SAST)
.github/dependabot.yml
terraform/aws/        ECR, OIDC role for GitHub Actions, ECS Fargate (dev+prod), Secrets Manager
terraform/github/     Repo creation, branch protection, environments, RBAC
```

## Why these choices ("maximally simple" but real)

- **Compute**: ECS on Fargate, one cluster, one service per environment,
  no load balancer — each task gets a public IP directly. Genuinely
  "containerized infrastructure" (built from the same `Dockerfile`, scanned
  like any other image) without the extra setup of a VPC/ALB stack.
- **No bootstrap step required**: unlike Lambda container images, ECS does
  not validate that the referenced image exists when you register a task
  definition — `terraform apply` succeeds immediately, tasks simply won't
  start healthy until the pipeline pushes a real image and deploys it.
- **Registry**: a single private ECR repo, versioned images tagged with the
  git commit SHA. Dev and Prod both point at the registry; promotion means
  deploying the tag Dev already validated to the Prod service — never a
  rebuild.
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
3. `deploy-dev` (env: `dev`) — registers a new ECS task definition revision pointing at that image, updates the Dev service, waits for it to stabilize, then curls the running task's `/health` endpoint as a smoke test.
4. `deploy-prod` (env: `production`) — **blocked until a required reviewer approves** the environment deployment in the GitHub UI, then deploys the *exact same* image to the Prod service and smoke-tests it the same way.

This is the Dev→Prod promotion logic: one build, one artifact, validated in Dev, promoted to Prod only after Dev succeeds and a human approves.

## Security controls (maps to acceptance criteria)

| Control | Where |
|---|---|
| No hardcoded secrets in pipeline | OIDC role assumption (`iam_oidc.tf`); no AWS keys anywhere. Real app secrets live in Secrets Manager and are read by the running task at runtime, never by the pipeline. |
| Least privilege for the CI/CD identity | `iam_oidc.tf` — the GitHub Actions role can only push to *this* ECR repo, deploy to *these two* ECS services, and `iam:PassRole` only the two ECS task/execution roles (scoped with `iam:PassedToService = ecs-tasks.amazonaws.com`). Nothing account-wide. |
| Least privilege at runtime | Each ECS task has its own execution role (pull image, write logs) and task role (read only its own Secrets Manager secret) — `ecs.tf`. |
| RBAC on the pipeline/repo | `terraform/github/branch_protection.tf` (`github_repository_collaborators`), GitHub Environment reviewers for `production`. |
| Branch protection | `branch_protection.tf` — required PR review, required status checks, no force-push, no deletion. |
| SAST | `codeql.yml`. |
| Dependency/vulnerability scanning | `npm audit` in `security-scan`; `github_repository_vulnerability_alerts` + Dependabot (`.github/dependabot.yml`) for automated update PRs. |
| Secret scanning | `gitleaks` in the pipeline **and** native GitHub secret scanning + push protection enabled via `github_repository.security_and_analysis` (public repos: free). |
| Container image scanning | Trivy in both `ci.yml` and `cd.yml` (fails the pipeline on CRITICAL/HIGH), plus ECR `scan_on_push` as a second, independent check. |
| Fail on critical findings | `exit-code: '1'` on every Trivy step; `npm audit --audit-level=high` exits non-zero on findings. |
| Secure artifact storage | ECR repo policy restricts pulls/pushes to this AWS account only (`ecr.tf`); images are immutable-tagged. |
| Environment-specific config without exposing secrets | Non-sensitive values (region, cluster/service name, role ARN) are GitHub **Environment variables**; actual secrets are pulled from AWS Secrets Manager by the running task, never passed through CI. |
| `.gitignore` | Repo root — excludes `.terraform/`, `*.tfstate`, `*.tfvars`, `.env*`, key files. |

## Deploying this yourself

Requires: an AWS account, a GitHub PAT (repo admin scope), Terraform >= 1.5, Docker, AWS CLI.

**1. Create the GitHub repo with security settings baked in**
```bash
cd terraform/github
export TF_VAR_github_token=...
terraform init
terraform apply -var github_owner=<you> -var repo_name=ci-cd-task \
                 -var 'production_reviewers=["<your-github-username>"]'

git remote add origin git@github.com:<you>/ci-cd-task.git
git push -u origin main
```

**2. Create the AWS infra (ECR, OIDC role, ECS cluster/services, Secrets Manager)**
```bash
cd ../aws
terraform init
terraform apply -var github_org=<you> -var github_repo=ci-cd-task
```

**3. Wire the two together: put terraform/aws outputs into terraform/github env vars**
```bash
cd ../github
terraform apply -var github_owner=<you> -var repo_name=ci-cd-task \
  -var 'production_reviewers=["<your-github-username>"]' \
  -var aws_github_actions_role_arn=$(cd ../aws && terraform output -raw github_actions_role_arn) \
  -var ecr_repository_url=$(cd ../aws && terraform output -raw ecr_repository_url) \
  -var ecs_cluster_name=$(cd ../aws && terraform output -raw ecs_cluster_name) \
  -var aws_region=eu-central-1
```

From then on: open a PR → `ci.yml` runs. Merge to `main` → `cd.yml` builds,
deploys to Dev, then waits for approval in the `production` GitHub
Environment before promoting to Prod.

## Notes / deliberate simplifications

- Terraform state is local by default (no `backend` block in
  `terraform/aws/main.tf`) to keep first-run friction low; add an S3 +
  DynamoDB remote backend for anything beyond a demo.
- No ALB/target groups — each Fargate task gets a public IP directly via
  `assign_public_ip = true`, and the security group opens port 8080 to
  `0.0.0.0/0`. Fine for a demo; put an ALB in front and lock the security
  group down to it for anything real.
- Only `dev` and `prod` are wired up; adding `qa` is copy/paste of one more
  entry in `local.environments` (`terraform/aws/main.tf`) and one more
  `github_repository_environment` block.
- Secret scanning / code scanning via native GitHub features require the
  repo to be public, or GitHub Advanced Security on a private repo — either
  way, gitleaks + CodeQL + Trivy in the pipeline itself work regardless of plan.
