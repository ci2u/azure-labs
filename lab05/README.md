# Lab 05 – Public Standard Load Balancer with Terraform

## What you build
```
                 Internet (only your IP is allowed by the NSG)
                              |
                 pip-lab05-lb (frontend "fe-public")
                              |
                          lb-lab05  (Standard)
   rule-http      :80    -> backend pool be-web :80   (probe-http: GET / every 5 s)
   nat-ssh-vm1    :50001 -> vm1:22
   nat-ssh-vm2    :50002 -> vm2:22
   outbound-all   VMs reach the Internet as the frontend IP (SNAT)
                 /                          \
   vm-lab05-vm1 10.50.1.4            vm-lab05-vm2 10.50.1.5
   nginx, no public IP               nginx, no public IP
```
- **Standard SKU** load balancer and public IP (Basic LB is retired)
- **Backend pool** with both NICs, **HTTP health probe**, **load-balancing rule** on port 80
- **Inbound NAT rules** – SSH to each VM through its own frontend port
- **Outbound rule** – the VMs have no public IPs but can still reach the Internet
- **NSG** on the subnet: a Standard LB is *secure by default*, nothing gets in without an Allow rule
- cloud-init installs nginx and writes `Hello from <hostname>` so you can see which VM answered

**Cost:** ~$0.25/h for the two VMs + ~$0.03/h for the LB and public IP (~$7/day). **Destroy at the end of every session.**

## Prerequisites
Same as Lab 01: Azure CLI, Terraform ≥ 1.6, `az login`, an SSH key at `~/.ssh/id_rsa.pub`.

## Steps (PowerShell, from this folder)
```powershell
Copy-Item ..\lab01\terraform.tfvars terraform.tfvars   # subscription_id + my_ip (check your IP: curl.exe -s ifconfig.me)
terraform init
terraform fmt; terraform validate
terraform plan -out tfplan        # read it! should be 22 to add
terraform apply tfplan
$rg  = terraform output -raw resource_group
$url = terraform output -raw url
terraform output ssh_commands
```
Give cloud-init 2–3 minutes after apply to install nginx. If `curl.exe $url` times out, SSH in and run `cloud-init status --wait`.

## Things to try (this is where the learning is)
1. **Load distribution.** Call the frontend ten times:
   ```powershell
   1..10 | ForEach-Object { curl.exe -s $url }
   ```
   You see a mix of `vm-lab05-vm1` and `vm-lab05-vm2`. The default mode hashes the **5-tuple** (source IP, source port, destination IP, destination port, protocol). Each `curl.exe` opens a new TCP connection from a new source port, so it can land on either VM. Now refresh the URL in a browser a few times – it tends to stick to one VM. Why? (Hint: keep-alive reuses the same connection, so the 5-tuple doesn't change.)

2. **Health probe and failover.** SSH to vm1 and stop nginx:
   ```powershell
   ssh -p 50001 azureuser@$(terraform output -raw lb_public_ip)
   ```
   ```bash
   sudo systemctl stop nginx
   ```
   Wait ~10 seconds, then run the loop from exercise 1 again in PowerShell – only vm2 answers. In the portal open **lb-lab05 → Monitoring → Metrics → Health Probe Status**, split by *Backend IP Address*, to see vm1 drop to 0%.
   - Notice your SSH session through `:50001` keeps working. **Inbound NAT rules don't use the health probe.**
   - Stop nginx on vm2 as well: the URL now **times out** – the LB has no healthy backend and doesn't return an error page.
   - Start nginx again on both (`sudo systemctl start nginx`).

3. **Session persistence.** In `terraform.tfvars` add `load_distribution = "SourceIP"` and run `terraform plan` – it's **1 to change** (only the rule). Apply, then run the loop again: every answer now comes from the same VM, because only source IP + destination IP are hashed. Portal name for this setting: *Session persistence: Client IP*. Remove the line and apply again.

4. **Inbound NAT rules.** SSH to both VMs and run `hostname`:
   ```powershell
   ssh -p 50001 azureuser@$(terraform output -raw lb_public_ip)
   ssh -p 50002 azureuser@$(terraform output -raw lb_public_ip)
   ```
   Same public IP, different port, different VM. Look at the NSG rule `Allow-SSH-MyIP`: it allows port **22**, not 50001/50002. Why? (The LB rewrites the destination before the packet reaches the NSG.)

5. **Outbound rule (SNAT).** The VMs have no public IP. On either VM:
   ```bash
   curl -s ifconfig.me
   ```
   It prints the **LB frontend IP**: the outbound rule translates the VMs' private source addresses to it. In `main.tf` the HTTP rule has `disable_outbound_snat = true` – outbound comes only from the explicit outbound rule, which gives each VM a fixed 1024 SNAT ports. When more than one outbound method applies, Azure uses: **NAT gateway → instance-level public IP → LB outbound rule → default outbound access** (being retired, don't rely on it).

6. **Break it with an NSG rule.** Add a deny-all rule *below* your allow rules but *above* the default rules:
   ```powershell
   az network nsg rule create -g $rg --nsg-name nsg-lab05-web -n Deny-All-In --priority 4000 --access Deny --direction Inbound --protocol "*" --source-address-prefixes "*" --destination-port-ranges "*"
   ```
   Wait ~15 seconds and run the loop. Your IP is still allowed at priority 100, so why does it time out? (Hint: who sends the health probes, and which default rule allowed them?) Fix it by adding an Allow rule for source `AzureLoadBalancer` with priority 3900 – or just delete the deny rule:
   ```powershell
   az network nsg rule delete -g $rg --nsg-name nsg-lab05-web -n Deny-All-In
   ```

7. **Quiz** (answer without the portal):
   - Basic vs Standard LB: which one needs an NSG to allow traffic, supports availability zones and has an SLA?
   - Load Balancer vs Application Gateway vs Traffic Manager vs Front Door – which are layer 4 vs layer 7, and which are regional vs global?
   - What source IP do health probes come from?
   - An *internal* LB in front of firewall NVAs needs to balance **all ports and protocols** with one rule – what is that feature called?

## Clean up – every time
```powershell
terraform destroy
```
The two VMs cost ~$6/day – don't leave them running.
