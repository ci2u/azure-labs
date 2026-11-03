# Lab 07 – Docker, Azure Container Registry and AKS

## What you build
```
  your PC                          Azure (rg-lab07)
  ───────                          ────────────────
  app/ ──docker build──► hello:v1 ──docker push──► acrlab07xxxx  (ACR Basic)
                                                        │ AcrPull for the kubelet identity
  kubectl ──(only from my_ip)──► aks-lab07 (Free tier, 1 node)
                                   └─ Deployment "hello" (2 pods) + ConfigMap
                                   └─ Service "hello" type LoadBalancer
                                                        │
                                MC_rg-lab07_aks-lab07_northeurope
                                (node VM scale set, Azure LB, public IPs)
```
- `app/` – a tiny Python web app that answers `Hello from <pod name> (version v1)`, plus its **Dockerfile** (non-root user, version baked in at build time)
- `k8s/` – **ConfigMap**, **Deployment** (2 replicas, readiness + liveness probes, rolling update) and **Service** (type LoadBalancer)
- Terraform (5 resources): **ACR** (admin user off), **AKS** (1 node, Azure CNI overlay, API server restricted to your IP) and the **AcrPull** role assignment for the cluster's kubelet identity

**Cost:** ~$0.13/h for the node + ~$0.03/h for its disk, load balancer and public IPs + $0.17/day for ACR Basic (~$4/day). The Free tier has no control-plane charge. **Destroy at the end of every session.**

## Prerequisites
- **Docker Desktop running** (whale icon in the tray says *Engine running*). Check with `docker info`.
- `kubectl` – comes with Docker Desktop
- Azure CLI, Terraform ≥ 1.6, `az login`

## Part 1 – Docker on your PC (free, do it before the apply)
From this folder (`lab07`):
```powershell
docker build -t hello:v1 --build-arg APP_VERSION=v1 app
docker images hello                       # how big is it? where does the size come from?
docker run -d --name hello -p 8080:8000 hello:v1
curl.exe http://localhost:8080            # Hello from <container id> (version v1)
docker ps                                 # running containers and the port mapping
docker logs hello                         # the app's stdout - one line per request
docker exec hello id                      # uid=10001 - not root, thanks to USER in the Dockerfile
docker run --rm -e GREETING=Czesc -p 8081:8000 hello:v1   # Ctrl+C to stop; config comes from env vars
docker stop hello; docker rm hello
```
Questions: what's the difference between an **image** and a **container**? What does `-p 8080:8000` map to what? Why does the hostname in the response look like a random ID?

## Part 2 – Deploy ACR and AKS
```powershell
Copy-Item ..\lab01\terraform.tfvars terraform.tfvars   # subscription_id + my_ip (check your IP: curl.exe -s ifconfig.me)
terraform init
terraform plan -out tfplan        # read it! should be 5 to add
terraform apply tfplan            # AKS takes 5–10 minutes
$rg      = terraform output -raw resource_group
$acrName = terraform output -raw acr_name
$acr     = terraform output -raw acr_login_server
```
The API server only accepts your IP. **If kubectl times out later, your IP has changed** – fix it with:
```powershell
terraform apply -var "my_ip=$(curl.exe -s ifconfig.me)/32"
```

## Things to try (this is where the learning is)
1. **Push the image to ACR.**
   ```powershell
   az acr login -n $acrName                     # gives Docker a token from your Entra ID login
   docker tag hello:v1 "$acr/hello:v1"          # an image name includes the registry
   docker push "$acr/hello:v1"
   az acr repository list -n $acrName -o table
   az acr repository show-tags -n $acrName --repository hello -o table
   ```
   The registry has no admin password (`admin_enabled = false`): you log in with your own identity and AKS pulls with its managed identity. (`az acr build`, which builds in the cloud without Docker, may be blocked on free-credit subscriptions.)

2. **Connect kubectl to the cluster.**
   ```powershell
   az aks get-credentials -g $rg -n aks-lab07 --overwrite-existing
   kubectl config get-contexts        # docker-desktop and aks-lab07 - the * marks the current one
   kubectl get nodes -o wide          # one node, which is a VM in the MC_ resource group
   kubectl get pods -A                # system pods AKS runs for you (CoreDNS, kube-proxy, ...)
   ```
   Look at the `MC_rg-lab07_aks-lab07_northeurope` resource group in the portal: a VM scale set, a load balancer called `kubernetes`, a public IP for outbound traffic. **AKS manages that group – don't change it by hand.**

3. **Deploy the app.**
   ```powershell
   kubectl apply -f k8s\configmap.yaml
   (Get-Content k8s\deployment.yaml -Raw).Replace('ACR_LOGIN_SERVER', $acr) | kubectl apply -f -
   kubectl apply -f k8s\service.yaml
   kubectl get pods -o wide -w        # Ctrl+C once both are Running and READY 1/1
   kubectl get svc hello -w           # wait for EXTERNAL-IP, then Ctrl+C
   $app = kubectl get svc hello -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   1..10 | ForEach-Object { curl.exe -s "http://$app" }
   ```
   Both pod names appear. In the portal, open the `kubernetes` load balancer in the MC_ group: AKS added a frontend IP and a rule for port 80 – the same pieces you built by hand in Lab 05.

4. **Self-healing and scaling.**
   ```powershell
   kubectl get pods
   kubectl delete pod <one of the pod names>
   kubectl get pods                   # a new pod with a new name is already starting
   kubectl scale deployment hello --replicas=4
   kubectl get pods -o wide           # all on the same node - there's only one
   kubectl scale deployment hello --replicas=2
   ```
   The **Deployment** keeps a **ReplicaSet** at the desired count; you never manage pods directly.

5. **Rolling update and rollback.**
   ```powershell
   docker build -t "$acr/hello:v2" --build-arg APP_VERSION=v2 app
   docker push "$acr/hello:v2"
   kubectl set image deployment/hello hello="$acr/hello:v2"
   kubectl rollout status deployment/hello
   1..10 | ForEach-Object { curl.exe -s "http://$app" }    # version v2
   kubectl rollout history deployment/hello
   kubectl rollout undo deployment/hello                   # back to v1
   ```
   Run the curl loop *during* the rollout and you see v1 and v2 mixed – pods are replaced one at a time (`maxSurge: 1`, `maxUnavailable: 0`).

6. **Debug a broken deployment.** Deploy a tag that doesn't exist:
   ```powershell
   kubectl set image deployment/hello hello="$acr/hello:v99"
   kubectl get pods                   # ErrImagePull / ImagePullBackOff
   kubectl describe pod <the new pod> # read the Events section at the bottom
   kubectl get events --sort-by=.lastTimestamp
   1..5 | ForEach-Object { curl.exe -s "http://$app" }     # still answering!
   kubectl rollout undo deployment/hello
   ```
   Why does the app keep working? (Hint: `maxUnavailable: 0` and the readiness probe.) What error would you see if the AcrPull role assignment were missing?

7. **Configuration from a ConfigMap.**
   ```powershell
   kubectl create configmap hello-config --from-literal=GREETING=Czesc --dry-run=client -o yaml | kubectl apply -f -
   1..3 | ForEach-Object { curl.exe -s "http://$app" }     # still "Hello"
   kubectl rollout restart deployment/hello
   kubectl rollout status deployment/hello
   1..3 | ForEach-Object { curl.exe -s "http://$app" }     # now "Czesc"
   ```
   Environment variables are read when a container starts, so a ConfigMap change only takes effect after a restart. Also try `kubectl logs deployment/hello` and `kubectl exec -it deployment/hello -- sh`.

8. **Quiz** (answer without looking):
   - Pod vs ReplicaSet vs Deployment – what does each one do?
   - Service types **ClusterIP**, **NodePort**, **LoadBalancer** – who can reach each?
   - Readiness probe vs liveness probe – what happens when each one fails?
   - Two ways to let AKS pull from ACR without passwords. (`az aks update --attach-acr`, or an AcrPull role assignment for the kubelet identity – both are the same thing.)
   - AKS **Free** vs **Standard** tier: what do you pay for, and what do you get?
   - What's in the `MC_` resource group, and what happens to it when you delete the cluster?

## Clean up – every time
```powershell
kubectl delete -f k8s\service.yaml   # releases the app's public IP cleanly
terraform destroy                    # deletes ACR, AKS and the whole MC_ resource group
kubectl config delete-context aks-lab07
kubectl config use-context docker-desktop
az group list -o json | ConvertFrom-Json | Where-Object name -like 'MC_*' | Select-Object -ExpandProperty name   # should print nothing
```
Optional local cleanup: `docker rmi hello:v1 "$acr/hello:v1" "$acr/hello:v2"`.
