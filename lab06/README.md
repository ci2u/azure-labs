# Lab 06 – Azure Monitor with Terraform

## What you build
```
   vm-lab06 ──Azure Monitor Agent──► DCR (Perf + Syslog) ──► law-lab06-xxxx
      │                                                      ▲
      │ platform metric "Percentage CPU"                     │ subscription activity log
      ▼                                                      │ (diagnostic setting)
   metric alert          log search alert          activity log alert
   CPU > 80% / 5 min     > 5 failed SSH / 5 min    VM deallocated
            \___________________ all three ___________________/
                                    │
                         ag-lab06-email ──► your inbox
```
- **Log Analytics workspace** with 30-day retention and a **0.5 GB daily cap**
- **Azure Monitor Agent** (VM extension) using the VM's **system-assigned managed identity**
- **Data collection rule** (DCR): CPU, memory and disk counters → `Perf` table; auth/daemon syslog → `Syslog` table
- **Diagnostic setting** that sends the subscription's activity log to the workspace → `AzureActivity` table
- **Action group** that emails you, and three alert types: **metric**, **log search** and **activity log**

**Cost:** ~$0.13/h for the VM (~$3/day). Log ingestion is a few MB (the first 5 GB/month are free), and the alerts cost cents per month. **Destroy at the end of every session.**

## Prerequisites
Same as Lab 01: Azure CLI, Terraform ≥ 1.6, `az login`, an SSH key at `~/.ssh/id_rsa.pub`.

## Steps (PowerShell, from this folder)
```powershell
Copy-Item ..\lab01\terraform.tfvars terraform.tfvars   # subscription_id + my_ip (check your IP: curl.exe -s ifconfig.me)
Add-Content terraform.tfvars 'alert_email = "you@example.com"'   # put your real address here
terraform init
terraform fmt; terraform validate
terraform plan -out tfplan        # read it! should be 18 to add
terraform apply tfplan
$rg = terraform output -raw resource_group
$ip = terraform output -raw public_ip
```
You get an email saying you were added to the action group – that's how you know email delivery works.

Data takes **5–10 minutes** to start arriving in the workspace after apply. Run all KQL queries in the portal: **Log Analytics workspaces → law-lab06-xxxx → Logs** (switch the editor to *KQL mode*).

## Things to try (this is where the learning is)
1. **Is the agent reporting?**
   ```kusto
   Heartbeat
   | where TimeGenerated > ago(15m)
   | summarize LastSeen = max(TimeGenerated) by Computer, Category
   ```
   You should see `vm-lab06` with category `Azure Monitor Agent`. If nothing appears after 15 minutes, check **vm-lab06 → Settings → Extensions + applications** (status of `AzureMonitorLinuxAgent`) and **Monitor → Data collection rules → dcr-lab06-linux → Resources**.

2. **Platform metrics vs guest metrics.** Open **vm-lab06 → Monitoring → Metrics**. *Percentage CPU* is there, but look for memory usage – you'll only find *Available Memory Bytes* (host view). Now query the counters the agent collected:
   ```kusto
   Perf
   | where TimeGenerated > ago(30m)
   | summarize avg(CounterValue) by ObjectName, CounterName, InstanceName
   ```
   **Platform metrics** come from the Azure host and need no agent. **Guest metrics** (used memory %, disk space per mount) need an agent inside the OS and a DCR.

3. **Metric alert: CPU.** SSH in and keep both vCPUs busy for 10 minutes:
   ```powershell
   ssh azureuser@$ip
   ```
   ```bash
   timeout 600 sh -c 'yes > /dev/null & yes > /dev/null & wait'
   ```
   Within ~5–7 minutes you get a **Fired** email; in the portal see **Monitor → Alerts**. When the load stops, the alert **resolves on its own** and you get a second email (metric alerts are *stateful*). Meanwhile, chart the guest view of the same load:
   ```kusto
   Perf
   | where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
   | summarize avg(CounterValue) by bin(TimeGenerated, 1m)
   | render timechart
   ```

4. **Log search alert: failed SSH logins.** From PowerShell, try to log in eight times as a user that doesn't exist:
   ```powershell
   1..8 | ForEach-Object { ssh -o BatchMode=yes -o ConnectTimeout=5 hacker@$ip exit }
   ```
   Find the attempts in the workspace:
   ```kusto
   Syslog
   | where Facility in ("auth", "authpriv")
   | where SyslogMessage has "invalid user"
   | project TimeGenerated, HostName, SyslogMessage
   ```
   The alert `alert-lab06-ssh-failures` runs a similar query every 5 minutes and fires when the count is over 5. Expect the email **10–15 minutes** after the attempts: ingestion delay + evaluation interval. Why is a log alert slower than a metric alert?

5. **Activity log alert: deallocate.**
   ```powershell
   az vm deallocate -g $rg -n vm-lab06
   ```
   You get an email within a few minutes. Then find who did it in the workspace (the diagnostic setting copied the activity log there):
   ```kusto
   AzureActivity
   | where OperationNameValue =~ "Microsoft.Compute/virtualMachines/deallocate/action"
   | project TimeGenerated, Caller, ActivityStatusValue, ResourceGroup
   ```
   Start the VM again with `az vm start -g $rg -n vm-lab06`. Notice the CPU metric alert can't fire while the VM is deallocated – there's no data.

6. **Alert processing rule (portal only).** Before a maintenance window you want to stop emails without deleting alerts. In **Monitor → Alerts → Alert processing rules → Create**: scope `rg-lab06`, rule type *Suppress notifications*, schedule *now* for 1 hour. Repeat exercise 4 – the alert still **fires** (you see it in Alerts) but no email arrives. Delete the processing rule afterwards (Terraform doesn't know about it).

7. **Quiz** (answer without the portal):
   - Metric alert vs log search alert vs activity log alert – which one would you use for: *a VM's CPU*, *a specific error in an application log*, *someone deleting a resource group*, *Azure service health incidents*?
   - How long does Azure keep the activity log by default, and how do you keep it for a year?
   - The Log Analytics agent (MMA/OMS) was retired in August 2024. What replaced it, and what does a DCR add?
   - What happens to ingestion when the workspace hits its daily cap?
   - What's the difference between an **action group** and an **alert processing rule**??

## Clean up – every time
```powershell
terraform destroy
```
If you created the alert processing rule in exercise 6, delete it first: Terraform refuses to delete a resource group that still contains resources it doesn't manage. Check nothing is left with `az group exists -n rg-lab06` – it should print `false`.
