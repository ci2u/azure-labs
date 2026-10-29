# Lab 03 – RBAC and Azure Policy with Terraform

## What you build
Everything is scoped to **one resource group** (`rg-lab03`), so the rest of your subscription is untouched. **Cost: free** (identities, roles and policies don't bill).

**RBAC**
- a user-assigned **managed identity** `id-lab03-operator` – a principal to hand roles to
- a **custom role** *Lab03 VM Operator* – read/start/restart/deallocate VMs, nothing else
- two **role assignments** for the identity at RG scope: built-in *Reader* + the custom role

**Azure Policy** (4 assignments at RG scope)

| Assignment | Definition | Effect |
|---|---|---|
| Only northeurope | built-in *Allowed locations* | Deny |
| Require tag `costcenter` | built-in *Require a tag on resources* | Deny |
| Deny public IPs | **custom** definition (JSON in `main.tf`) | Deny |
| Inherit `environment` tag from RG | built-in *Inherit a tag from the resource group if missing* | **Modify** – needs its own managed identity + Contributor role |

## Prerequisites
Same as before: Azure CLI, Terraform ≥ 1.6, `az login`. You need **Owner** (or User Access Administrator) on the subscription to create roles and role assignments.

## Steps (PowerShell, from this folder)
```powershell
Copy-Item ..\lab01\terraform.tfvars terraform.tfvars   # only subscription_id is used; my_ip is ignored with a warning
terraform init
terraform fmt; terraform validate
terraform plan -out tfplan        # read it! should be 12 to add
terraform apply tfplan
$rg = terraform output -raw resource_group
```

> New policy assignments can take **5–30 minutes** to start enforcing. If an exercise that should be denied succeeds, wait and try again (and delete what got created).

## Things to try (this is where the learning is)
1. **See what's assigned:**
   ```powershell
   az policy assignment list -g $rg --query "[].{name:name, display:displayName, mode:enforcementMode}" -o table
   az role assignment list -g $rg --query "[].{who:principalName, role:roleDefinitionName}" -o table
   az role definition list --custom-role-only true --query "[].{name:roleName, actions:permissions[0].actions}" -o json
   ```

2. **Deny – required tag:** VNets are free, so they're good for testing.
   ```powershell
   az network vnet create -g $rg -n vnet-test1 --address-prefix 10.30.0.0/16
   ```
   Fails with **RequestDisallowedByPolicy** – read which assignment blocked it. Now add the tag:
   ```powershell
   az network vnet create -g $rg -n vnet-test1 --address-prefix 10.30.0.0/16 --tags costcenter=cc-1234
   az network vnet show -g $rg -n vnet-test1 --query tags
   ```
   It's created – and it has an **`environment` tag you never set**. That's the Modify policy copying it from the RG. (Modify runs *before* Deny is evaluated.)

3. **Deny – allowed locations:** the RG is in North Europe, but a resource inside it can be anywhere – unless policy says no:
   ```powershell
   az network vnet create -g $rg -n vnet-test2 -l westeurope --address-prefix 10.31.0.0/16 --tags costcenter=cc-1234
   ```

4. **Custom policy:** look at the `policy_rule` of `azurerm_policy_definition.deny_public_ip` in `main.tf`, then:
   ```powershell
   az network public-ip create -g $rg -n pip-test --sku Standard --tags costcenter=cc-1234
   ```

5. **Compliance and remediation** (the Modify effect only fixes *new or updated* resources – existing ones need a remediation task):
   ```powershell
   # switch the inherit-tag policy off, create a resource, switch it back on
   az policy assignment update -n inherit-environment-tag -g $rg --enforcement-mode DoNotEnforce
   az network vnet create -g $rg -n vnet-test3 --address-prefix 10.32.0.0/16 --tags costcenter=cc-1234
   az network vnet show -g $rg -n vnet-test3 --query tags          # no 'environment' tag
   az policy assignment update -n inherit-environment-tag -g $rg --enforcement-mode Default

   az policy state trigger-scan -g $rg                             # takes a few minutes
   az policy state summarize -g $rg --query "policyAssignments[].{assignment:policyAssignmentId, nonCompliant:results.nonCompliantResources}" -o table

   az policy remediation create -g $rg -n fix-env-tag --policy-assignment inherit-environment-tag
   az policy remediation show -g $rg -n fix-env-tag --query "{state:provisioningState, deployments:deploymentStatus}"
   az network vnet show -g $rg -n vnet-test3 --query tags          # 'environment' is back
   ```
   Also look at **Policy → Compliance** in the portal. (`terraform plan` will now show the enforcement mode drift as fixed – it isn't, because you set it back. Check!)

6. **RBAC – check access:** in the portal open **rg-lab03 → Access control (IAM) → Check access**, pick *Managed identity → id-lab03-operator*. Which roles does it have, and where do they come from? Then open **Roles**, find *Lab03 VM Operator* and look at its **JSON**. Questions:
   - Could this identity create a VM in the RG? Delete one? Start one?
   - Would it have any access in a *different* resource group? (Scope!)
   - Why can't you assign this custom role at subscription scope? (`assignable_scopes`)

7. **Resource locks** (they beat RBAC – even Owner is blocked):
   ```powershell
   az lock create -n no-delete --lock-type CanNotDelete -g $rg
   az network vnet delete -g $rg -n vnet-test1        # ScopeLocked
   az lock delete -n no-delete -g $rg

   az lock create -n read-only --lock-type ReadOnly -g $rg
   az network vnet update -g $rg -n vnet-test1 --set tags.test=1    # ScopeLocked - ReadOnly blocks changes too
   az lock delete -n read-only -g $rg
   ```
   **Remove every lock before cleaning up** – a lock also blocks `terraform destroy`.

## Clean up – every time
The test VNets weren't created by Terraform, and azurerm refuses to delete a resource group that still contains unmanaged resources. Delete them first:
```powershell
az lock list -g $rg -o table                      # must be empty
az network vnet delete -g $rg -n vnet-test1
az network vnet delete -g $rg -n vnet-test3
terraform destroy
```
