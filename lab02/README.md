# Lab 02 – Storage account with Terraform

## What you build
Resource group → StorageV2 account (Standard LRS, Hot, TLS 1.2, no anonymous access) with:
- blob **versioning** + **soft delete** (7 days for blobs and containers)
- a private **`data`** container
- a **lifecycle rule**: Cool after 30 days → Archive after 90 → delete after 365; old versions deleted after 30
- a **storage firewall**: default Deny, only your IP allowed
- an **RBAC data role** for you (*Storage Blob Data Contributor*) so you can use your Entra login instead of keys
- a **private endpoint** for blob in a VNet (10.20.0.0/16) + the `privatelink.blob.core.windows.net` private DNS zone

No VMs, so no quota problems. Cost is a few cents per session (private endpoint ~$0.01/h, DNS zone ~$0.50/month, storage pennies).

## Prerequisites
Same as Lab 01: Azure CLI, Terraform ≥ 1.6, `az login`.

## Steps (PowerShell, from this folder)
```powershell
Copy-Item terraform.tfvars.example terraform.tfvars   # fill in subscription_id and my_ip
terraform init
terraform fmt; terraform validate
terraform plan -out tfplan        # read it! should be 11 to add
terraform apply tfplan
```
Then save the names you'll use below:
```powershell
$st = terraform output -raw storage_account_name
$c  = terraform output -raw container_name
```

> The role assignment can take **a few minutes** to take effect. If the first `--auth-mode login` command says *AuthorizationPermissionMismatch*, wait and retry.

## Things to try (this is where the learning is)
1. **Upload with your Entra identity (no keys):**
   ```powershell
   "hello lab02" | Out-File hello.txt -Encoding ascii
   az storage blob upload --account-name $st --container-name $c --name hello.txt --file hello.txt --auth-mode login
   az storage blob list --account-name $st --container-name $c --auth-mode login -o table
   ```
   Why did Owner on the subscription not let you read blobs before the role assignment? (Control plane vs data plane.)

2. **Versioning and soft delete:** change `hello.txt`, upload it again with `--overwrite`, then list versions:
   ```powershell
   az storage blob list --account-name $st --container-name $c --include v --auth-mode login -o table
   ```
   Delete the blob, list with `--include d`, and bring it back with `az storage blob undelete`. Find both in the portal under *Containers → data → Show deleted blobs / versions*.

3. **User delegation SAS (signed with your Entra login, not the account key):**
   ```powershell
   $exp = (Get-Date).ToUniversalTime().AddHours(1).ToString("yyyy-MM-ddTHH:mmZ")
   az storage blob generate-sas --account-name $st --container-name $c --name hello.txt --permissions r --expiry $exp --as-user --auth-mode login --full-uri -o tsv
   ```
   Open the URL in your browser – it works. Remove the `?sv=...` part – it fails. What's the difference between an account SAS, a service SAS and a user delegation SAS?

4. **Storage firewall:** in `terraform.tfvars` set `my_ip` to a wrong address (`"1.2.3.4/32"`), `terraform apply`, and repeat the `az storage blob list` from step 1. You get *AuthorizationFailure* even though RBAC allows you – network rules are checked first. Put your real IP back and apply.

5. **Private endpoint DNS:**
   ```powershell
   nslookup "$st.blob.core.windows.net"
   ```
   From your laptop the name CNAMEs to `<name>.privatelink.blob.core.windows.net` but still resolves to a **public** IP. Inside the VNet it would resolve to the private IP: compare with `terraform output private_endpoint_ip` and the A record in the private DNS zone in the portal.

6. **Access tiers:**
   ```powershell
   az storage blob set-tier --account-name $st --container-name $c --name hello.txt --tier Archive --auth-mode login
   az storage blob download --account-name $st --container-name $c --name hello.txt --file out.txt --auth-mode login
   ```
   The download fails – Archive blobs must be **rehydrated** first (`--tier Hot --rehydrate-priority Standard`, takes hours). Look at the lifecycle rule in the portal under *Data management → Lifecycle management*.

7. **In-place vs replace (again):** change `account_replication_type` to `"GRS"` and plan – then change `account_kind` to `"BlobStorage"` and plan. Revert both with `git restore main.tf`.

## Clean up – every time
```powershell
terraform destroy
Remove-Item hello.txt, out.txt -ErrorAction SilentlyContinue
```
Soft-deleted blobs go away with the account. Storage is cheap, but the private endpoint and DNS zone bill while they exist.
