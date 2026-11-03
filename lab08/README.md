# Lab 08 – CI/CD with GitHub Actions

## What you build
```
  git push to main
        │
        ▼
  GitHub Actions: .github/workflows/lab08-ci-cd.yml   (repo root, not in lab08/)
  ┌────────┐   ┌──────────────────┐   ┌──────────────────────────┐
  │  test  │──►│ build + push     │──►│ deploy + smoke test      │
  │unittest│   │ hello:<sha>→ACR  │   │ az containerapp update   │
  └────────┘   └──────────────────┘   └──────────────────────────┘
                     │  OIDC token, subject "repo:ci2u/azure-labs:ref:refs/heads/main"
                     ▼
  Azure: id-lab08-github (user-assigned managed identity + federated credential)
         ├─ AcrPush     on acrlab08xxxx
         └─ Contributor on rg-lab08
  ca-lab08 (Container Apps, scales to zero) ── pulls with id-lab08-pull (AcrPull) ──► ACR
```
- `app/` – the hello app from Lab 07 (now on port 8080) plus **unit tests** (`test_app.py`) the pipeline runs first
- `../.github/workflows/lab08-ci-cd.yml` – the pipeline: **test → build and push → deploy → smoke test**
  - pull requests only run the tests; pushes to `main` run everything
  - images are tagged with the **commit SHA**, and the app shows that SHA as its version
- Terraform (12 resources): ACR, a Container Apps environment and app, two managed identities, and an **OIDC federated credential** – GitHub logs in to Azure **without any password or secret**

**Cost:** ACR Basic ~$0.17/day. Container Apps scales to zero and the monthly free grant covers this lab; GitHub Actions minutes are free. So this lab costs almost nothing, but still **destroy it when you're done**.

## Prerequisites
- Azure CLI, Terraform ≥ 1.6, `az login`
- Container Apps isn't registered on your subscription yet (one-time, takes a minute or two):
  ```powershell
  az provider register -n Microsoft.App --wait
  ```
- Optional for step 1: Docker Desktop running

## Setup (PowerShell, from this folder)
1. **Run the tests locally** – the same command the pipeline runs, inside a Python container because Python isn't installed on your PC:
   ```powershell
   docker run --rm -v "${PWD}\app:/app" -w /app python:3.12-slim python -m unittest -v
   ```
2. **Create the Azure side:**
   ```powershell
   Copy-Item ..\lab01\terraform.tfvars terraform.tfvars   # only subscription_id is needed; my_ip is ignored with a warning – delete that line
   terraform init
   terraform plan -out tfplan        # read it! should be 12 to add
   terraform apply tfplan
   terraform output app_url          # open it - for now it's a placeholder ASP.NET sample page
   terraform output github_variables
   ```
3. **Give GitHub the IDs.** On github.com open your `azure-labs` repo → **Settings → Secrets and variables → Actions → Variables tab → New repository variable**, and create the six variables from `github_variables` (same names, same values). They're IDs and names, not secrets – OIDC means there's nothing secret to store.
4. **Commit and push** `lab08/` and `.github/` (`terraform.tfvars` and the state stay out thanks to `.gitignore`):
   ```powershell
   cd ..
   git add lab08 .github
   git commit -m "lab08 CI/CD pipeline"
   git push
   ```
5. On GitHub open the **Actions** tab → **lab08 CI/CD** → the running workflow. When it's green, refresh the app URL:
   `Hello from ca-lab08--xxxxxxx-... (version abc1234)` – compare with `git log -1 --format=%h`.

## Things to try (this is where the learning is)
1. **Read the run.** Click each job and step. Find *Azure login (OIDC)*: where is the password? (There isn't one: GitHub issues a signed token for this job, and Azure trusts it because issuer + audience + subject match the federated credential.) In the portal see **id-lab08-github → Settings → Federated credentials**.

2. **Deploy a change.** In `app/app.py` change the default `GREETING` to something else, commit, push. When the run is green:
   ```powershell
   az containerapp revision list -n ca-lab08 -g rg-lab08 -o table
   az acr repository show-tags -n <acr name> --repository hello -o table
   ```
   Each deployment created a new **revision** and a new **image tag** – one per commit.

3. **Break a test.** In `build_message` change `from` to `on` (don't touch the tests). Push. The **test** job fails, **build** and **deploy** never run, and the live app still serves the previous version. That's the point of CI: a broken commit doesn't reach production. Fix it and push again.

4. **Pull request flow.**
   ```powershell
   git switch -c greeting-change
   # edit GREETING in app/app.py, then:
   git commit -am "Change greeting"
   git push -u origin greeting-change
   ```
   Open a pull request on GitHub. Only **test** runs; **build** shows as *skipped* (`if: github.event_name != 'pull_request'`). Why should a PR – maybe from someone else's fork – never get Azure access? Merge the PR and watch the full pipeline run on `main`.

5. **The OIDC subject is the security boundary.** Create a branch and push it (`git switch -c test-branch; git push -u origin test-branch`). On GitHub: **Actions → lab08 CI/CD → Run workflow**, pick `test-branch`. The build fails at *Azure login* with `AADSTS700213: No matching federated identity record found for presented assertion subject 'repo:ci2u/azure-labs:ref:refs/heads/test-branch'`. Only `main` is trusted – a stolen workflow on another branch gets nothing.

6. **Roll back.** The app runs the latest commit. Deploy an older image by hand:
   ```powershell
   az containerapp update -n ca-lab08 -g rg-lab08 --image <acr name>.azurecr.io/hello:<older sha>
   ```
   It works – but now Git says one thing and production another. What's the better rollback in a CI/CD world? (Hint: `git revert` + push.)

7. **Approval before production.** On GitHub: **Settings → Environments → New environment** `production` → tick **Required reviewers** and add yourself (free for public repos; private repos need a paid plan). In the workflow add `environment: production` to the `deploy` job (same level as `needs:`), push, and approve the deployment when GitHub asks. The deploy job's token subject is now `repo:ci2u/azure-labs:environment:production` – Terraform already created a federated credential for it. What would have happened without it?

8. **Least privilege.** What can the pipeline identity do?
   ```powershell
   az role assignment list --assignee (terraform output -json github_variables | ConvertFrom-Json).AZURE_CLIENT_ID --all -o table
   ```
   *Contributor* on the resource group means it could also delete the registry. How would you narrow it? (A role scoped to just the container app, e.g. *Container Apps Contributor*, plus AcrPush on the registry.)

9. **Quiz:**
   - Continuous integration vs continuous delivery vs continuous deployment?
   - Three reasons OIDC is better than storing a service principal's client secret in GitHub.
   - Why tag images with the commit SHA instead of `latest`?
   - What do `needs:` and `if:` do in a workflow?
   - In a real team, how would Terraform itself run in a pipeline? (Remote state backend, `plan` on pull requests, `apply` on `main` after approval.)

## Clean up
```powershell
terraform destroy
```
Then on GitHub either delete the six variables or disable the workflow (**Actions → lab08 CI/CD → ⋯ → Disable workflow**), otherwise the next push to `lab08/app` will fail at the build job.
