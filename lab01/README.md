# Lab 01 – Linux VM with Terraform

## What you build
Resource group → VNet (10.10.0.0/16) → subnet with an NSG (SSH from your IP only, HTTP open) → Standard public IP → NIC → Ubuntu 24.04 confidential VM (Standard_DC2as_v6, AMD SEV-SNP).

> Why not B1s? It is `NotAvailableForSubscription` in Polandcentral. DC2as_v6 (~$0.12/h on Linux) is available, but it is a *confidential* VM size: it needs Secure Boot, vTPM, `security_encryption_type` on the OS disk and the Ubuntu `cvm` image SKU – all set in `main_1.tf`.

## Prerequisites
- Azure CLI, Terraform ≥ 1.6, an SSH key (`ssh-keygen -t rsa -b 4096` if you don't have one)
- `az login`

## Steps
```bash
cp terraform.tfvars.example terraform.tfvars   # fill in subscription_id and my_ip
terraform init
terraform fmt && terraform validate
terraform plan -out tfplan        # read it! count the resources (should be 8)
terraform apply tfplan
ssh azureuser@$(terraform output -raw public_ip)
```

## Things to try (this is where the learning is)
1. **Drift:** in the portal, add a tag to the VM by hand. Run `terraform plan` – what does Terraform want to do?
2. **In-place vs replace:** change `vm_size` to `Standard_DC4as_v6` and plan. Then change the image to Ubuntu 22.04 CVM (offer `0001-com-ubuntu-confidential-vm-jammy`, SKU `22_04-lts-cvm`) and plan. (Stay on DC*as sizes and CVM images – a non-confidential size or image won't deploy with this config.) Why is one an update and the other a destroy/create?
3. **NSG troubleshooting (AZ-104 favourite):** remove your IP from the SSH rule, apply, and use *Network Watcher → IP flow verify* in the portal to prove which rule blocks you.
4. **State:** run `terraform state list` and `terraform state show azurerm_linux_virtual_machine.vm`.
5. **CLI equivalent:** recreate just the resource group + VNet with `az group create` / `az network vnet create` so you know both ways.

## Clean up – every time
```bash
terraform destroy
```
A DC2as_v6 VM costs ~$88/month if left running, and leftover public IPs and disks still bill. Destroy at the end of each session.
