# Lab 04 – Hub and spoke networking with Terraform

## What you build
```
                  vnet-hub 10.40.0.0/16
                  snet-shared 10.40.1.0/24   ("NVA" address 10.40.1.4 – nothing deployed)
                 /                        \
         peering (both ways)        peering (both ways)
               /                            \
 vnet-spoke1 10.41.0.0/16             vnet-spoke2 10.42.0.0/16
 nsg-spoke1                           nsg-spoke2
 vm-lab04-spoke1 10.41.1.4            vm-lab04-spoke2 10.42.1.4
 public IP, ASG asg-jump              private only, ASG asg-app
```
- **VNet peering** hub ↔ spoke1 and hub ↔ spoke2 (each direction is its own resource)
- **Application security groups**: `asg-jump` (spoke1 VM), `asg-app` (spoke2 VM)
- **NSG rules written against ASGs**: SSH from your IP to `asg-jump`; to `asg-app` only ICMP is allowed from the VNet, everything else denied
- an optional **user-defined route** (`enable_udr`) for exercise 5
- two Ubuntu confidential VMs (Standard_EC2as_v5) – together your whole 4-core quota

**Cost:** ~$0.25/h for the two VMs (~$6/day) plus a few cents for the public IP. **Destroy at the end of every session.**

## Prerequisites
Same as Lab 01: Azure CLI, Terraform ≥ 1.6, `az login`, an SSH key at `~/.ssh/id_rsa.pub`.

## Steps (PowerShell, from this folder)
```powershell
Copy-Item ..\lab01\terraform.tfvars terraform.tfvars   # subscription_id + my_ip (check your IP: curl.exe -s ifconfig.me)
terraform init
terraform fmt; terraform validate
terraform plan -out tfplan        # read it! should be 24 to add
terraform apply tfplan
$rg = terraform output -raw resource_group
ssh azureuser@$(terraform output -raw jump_public_ip)
```

## Things to try (this is where the learning is)
1. **Peering status:**
   ```powershell
   az network vnet peering list -g $rg --vnet-name vnet-hub --query "[].{name:name, state:peeringState, sync:peeringSyncLevel, fwd:allowForwardedTraffic}" -o table
   ```
   Both should be **Connected**. Delete one direction in the portal and see the other become **Disconnected**, then `terraform apply` to recreate it.

2. **Peering is not transitive.** On `vm-lab04-spoke1` (via SSH):
   ```bash
   ping -c 3 10.42.1.4      # spoke2 VM - fails
   ```
   Both spokes are peered with the hub, so why not with each other? Look at the routes the spoke1 NIC actually has and ask Network Watcher where the packet goes:
   ```powershell
   az network nic show-effective-route-table -g $rg -n nic-lab04-spoke1 -o table
   az network watcher show-next-hop -g $rg --vm vm-lab04-spoke1 --source-ip 10.41.1.4 --dest-ip 10.42.1.4
   ```
   There's a `VNetPeering` route for 10.40.0.0/16 (hub) but **none for 10.42.0.0/16** – next hop is `Internet`, where a private address goes nowhere.

3. **Fix it with a direct spoke-to-spoke peering** (both directions):
   ```powershell
   az network vnet peering create -g $rg -n spoke1-to-spoke2 --vnet-name vnet-spoke1 --remote-vnet vnet-spoke2 --allow-vnet-access
   az network vnet peering create -g $rg -n spoke2-to-spoke1 --vnet-name vnet-spoke2 --remote-vnet vnet-spoke1 --allow-vnet-access
   ```
   `ping -c 3 10.42.1.4` from spoke1 now works, and the effective route table shows 10.42.0.0/16 → `VNetPeering`. (Other real-world answers: an NVA/Azure Firewall in the hub + UDRs, a VPN gateway with *gateway transit*, or Virtual WAN.)

4. **NSG + ASG:** ping works, but SSH from spoke1 to spoke2 doesn't. On `vm-lab04-spoke1`:
   ```bash
   nc -zv -w 3 10.42.1.4 22     # times out
   ```
   Find out which rule blocks it – without looking at the NSG:
   ```powershell
   az network watcher test-ip-flow -g $rg --vm vm-lab04-spoke2 --direction Inbound --protocol TCP --local 10.42.1.4:22 --remote 10.41.1.4:50000
   az network watcher test-ip-flow -g $rg --vm vm-lab04-spoke2 --direction Inbound --protocol TCP --local 10.42.1.4:22 --remote 10.41.1.4:50000 --query ruleName
   az network nic list-effective-nsg -g $rg -n nic-lab04-spoke2 --query "value[0].effectiveSecurityRules[].{name:name, prio:priority, access:access, proto:protocol, dst:destinationAddressPrefix}" -o table
   ```
   Notice how the ASG rules expand to the NIC's IP in the effective rules. Why is `Deny-VNet-to-App` (4000) needed at all? (Hint: `AllowVnetInBound` at 65000 – and the `VirtualNetwork` tag includes **peered** VNets.)

5. **User-defined route beats the peering route.** Keep the spoke1↔spoke2 peering from step 3, then in `terraform.tfvars` add `enable_udr = true` and `terraform apply`. Ping spoke2 from spoke1 again – it fails. Ask Network Watcher why:
   ```powershell
   az network watcher show-next-hop -g $rg --vm vm-lab04-spoke1 --source-ip 10.41.1.4 --dest-ip 10.42.1.4
   az network nic show-effective-route-table -g $rg -n nic-lab04-spoke1 -o table
   ```
   Next hop is `VirtualAppliance 10.40.1.4` – the UDR (source `User`) replaced the `VNetPeering` route for the same prefix, and there's no NVA at that address. Route selection: **longest prefix match first; for equal prefixes, User > BGP > System.** Set `enable_udr = false` (or remove it) and apply again.

6. **Peering settings quiz** (check them in the portal on a peering): what do *Allow forwarded traffic*, *Allow gateway transit* and *Use remote gateways* each do, and which side of the peering must set each one?

## Clean up – every time
```powershell
az network vnet peering delete -g $rg -n spoke1-to-spoke2 --vnet-name vnet-spoke1
az network vnet peering delete -g $rg -n spoke2-to-spoke1 --vnet-name vnet-spoke2
terraform destroy
```
The two VMs cost ~$6/day – don't leave them running.
