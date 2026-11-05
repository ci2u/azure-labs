# Lab 09 – Terraform in a pipeline (remote state, plan on PR, apply after approval)

## What you build
```
  bootstrap/  (run once from your PC, local state)
  ──────────
  rg-lab09-tfstate
    ├─ stlab09tfstateXXXX / tfstate      ← remote state: versioning, soft delete, RBAC, blob-lease locking
    ├─ id-lab09-plan   OIDC: pull_request + main          → Reader on rg-lab09
    └─ id-lab09-apply  OIDC: environment "production"     → Contributor on rg-lab09
  rg-lab09                                                ← the ONLY place the pipeline can change

  stack/  (deployed only by .github/workflows/lab09-terraform.yml)
  ──────
  vnet-lab09 ── snet-web (NSG: HTTPS in, SSH denied)
             └─ snet-app

  pull request ──► plan (fmt, validate, plan) ──► plan posted as a PR comment
  merge to main ──► plan ──► tfplan artifact ──► [approval: production] ──► apply tfplan
```
**The rule from now on: nobody runs `terraform apply` on `stack/` from a laptop.** Git is the only way to change it.

**Cost:** almost nothing. VNets, subnets and NSGs are free; the state storage account costs cents per month. You can leave it running between sessions.

## Prerequisites
- Azure CLI, Terraform ≥ 1.6, `az login`
- GitHub variables `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` from Lab 08 (without quotes!)
- Optional: GitHub CLI `gh` (`gh auth login`) to set variables in one go

## Setup (PowerShell)
1. **Bootstrap** (from `lab09\bootstrap`):
   ```powershell
   Copy-Item ..\..\lab08\terraform.tfvars terraform.tfvars   # keep subscription_id; github_repo has the right default
   terraform init
   terraform plan -out tfplan        # read it! should be 15 to add
   terraform apply tfplan
   ```
   If an apply fails with a 409 or "already exists" on a federated credential or role assignment, just run `terraform apply` again – Entra ID is eventually consistent.

2. **GitHub variables** – four new ones. With the GitHub CLI (no copy-paste, no stray quotes):
   ```powershell
   $vars = terraform output -json github_variables | ConvertFrom-Json
   $vars.PSObject.Properties | ForEach-Object { gh variable set $_.Name --body $_.Value --repo ci2u/azure-labs }
   gh variable list --repo ci2u/azure-labs
   ```
   (Or add them by hand: **Settings → Secrets and variables → Actions → Variables**.)

3. **The `production` environment** – if you didn't create it in Lab 08 exercise 7: **Settings → Environments → New environment** `production`. Tick **Required reviewers** and add yourself. (Required reviewers are free on public repos; on a private repo with a free plan the option isn't available – the pipeline still works, it just applies without waiting.)

4. **Local init and plan – look, don't touch** (from `lab09\stack`):
   ```powershell
   $env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
   Invoke-Expression (terraform -chdir=..\bootstrap output -raw backend_init_command)
   terraform plan                    # 5 to add - reads the remote state with YOUR az login
   ```
   This also creates `.terraform.lock.hcl` – commit it, so the plan and apply jobs use the same provider version. **Don't apply.**

5. **First change through a pull request:**
   ```powershell
   cd ..\..
   git switch -c lab09-network
   git add lab09 .github/workflows/lab09-terraform.yml
   git status                        # no terraform.tfvars, *.tfstate or tfplan
   git commit -m "lab09: terraform pipeline and network stack"
   git push -u origin lab09-network
   ```
   Open a pull request on GitHub. The **plan** job runs and posts a comment with the plan (5 to add). Review it, then **merge**.

6. **Apply after approval.** The merge to `main` starts the workflow again: **plan → apply**. The apply job waits with *Review deployments* – approve it. When it's green:
   ```powershell
   az resource list -g rg-lab09 -o table     # vnet-lab09, nsg-lab09-web
   git switch main; git pull
   ```

## Things to try (this is where the learning is)
1. **Look at the state.** Portal → `stlab09tfstateXXXX` → Containers → `tfstate` → `lab09.tfstate`. Open **Versions**: one per apply. Re-run the workflow manually (**Actions → lab09 Terraform → Run workflow**, branch `main`) and refresh the blob while *terraform plan* runs: **Lease state: Leased** – that's the state lock. Why must a plan take the lock too?

2. **A normal change.** On a new branch add a third subnet `snet-data` (`10.20.3.0/24`) to `stack/main.tf`, push, open a PR. Read the plan comment: `1 to add`. Merge, approve, check it exists.

3. **Least privilege in action.** On a branch, add a resource OUTSIDE `rg-lab09`:
   ```hcl
   resource "azurerm_resource_group" "sneaky" {
     name     = "rg-lab09-sneaky"
     location = "northeurope"
   }
   ```
   The PR plan succeeds (a plan only *reads*). Merge and approve: apply fails with `AuthorizationFailed` – the apply identity is Contributor on `rg-lab09` only. Fix it the CI/CD way: `git revert` the merge commit (`git revert -m 1 <sha>`), PR, merge. Note that the failed apply changed nothing.

4. **Drift.** In the portal add an inbound rule to `nsg-lab09-web` (e.g. allow port 8080). Run the workflow manually on `main`: the plan wants to **remove** your rule, and after approval it does. Who wins – the portal or Git? Then make it automatic: add a `schedule:` trigger (`- cron: "0 6 * * *"`) to the workflow. What should a scheduled run do – apply, or only report? (Hint: look at the `apply` job's `if:` and think about who approves at 7 am.)

5. **Concurrency and stale plans.** Merge two PRs quickly one after the other. The second workflow run **waits** (`concurrency:` group). What would happen without it? And if you approve an old apply after a newer one already ran, Terraform refuses with *Saved plan is stale* – why is that a feature?

6. **No more storage keys.** In `bootstrap/main.tf` set `shared_access_key_enabled = false`, and add `storage_use_azuread = true` to the bootstrap's provider block. Apply the bootstrap locally. The pipeline keeps working (it never used keys – `use_azuread_auth`). Try `az storage blob list --account-name <account> -c tfstate --auth-mode key` – what happens?

7. **Chicken and egg.** The bootstrap state is still on your PC. Move it into the storage account it created: add a `backend "azurerm"` block (key `bootstrap.tfstate`) to `bootstrap/versions.tf` and run `terraform init -migrate-state`. What's the risk if that storage account is ever deleted? (That's why real teams protect it with a **resource lock** – add one with `azurerm_management_lock`, `CannotDelete`.)

8. **Quiz:**
   - Why is the state storage account in a different resource group from what the pipeline manages?
   - Why does `plan` run with a Reader identity and `apply` with a Contributor identity, instead of one identity for both?
   - Why apply the saved `tfplan` instead of running `terraform apply -auto-approve` in the apply job?
   - What does `terraform plan -detailed-exitcode` return, and how does the workflow use it?
   - The plan comment on a PR shows `1 to destroy` for a subnet. What would you check before approving?
   - Why does `resource_provider_registrations = "none"` matter for these pipeline identities?

## Clean up
The stack goes first (the pipeline can't run `destroy` – that's on purpose), then the bootstrap:
```powershell
cd lab09\stack
$env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
terraform destroy
cd ..\bootstrap
terraform destroy
```
If you did exercise 7, migrate the bootstrap state back first (remove the backend block, `terraform init -migrate-state`); if you did the lock in exercise 7, delete it first. Then disable the workflow on GitHub (**Actions → lab09 Terraform → ⋯ → Disable workflow**).
