<!-- Author: Madhusudan Kharote - SWE645 Homework 2
     Purpose: Overview of the project and quick-start instructions to build, deploy and
     run the CI/CD pipeline for the containerized survey application. -->

# SWE 645 – Homework 2: Survey App on Kubernetes with Jenkins CI/CD

**Author:** Madhusudan Kharote (individual submission, all work by me)

This project takes the Homework 1 (Part 2) student survey website, containerizes it with Docker, deploys it on an **Amazon EKS** Kubernetes cluster with three self-healing pods, and delivers every change automatically through a **Jenkins CI/CD pipeline** triggered by pushes to GitHub.

| Item | Value |
|---|---|
| GitHub repository | https://github.com/Madhusudan01/swe645-hw2 |
| Docker Hub image | `mkharote/swe645-survey` (https://hub.docker.com/r/mkharote/swe645-survey) |
| Kubernetes cluster | Amazon EKS `swe645-cluster`, region `us-east-1`, 2 × t3.medium nodes |
| AWS environment | AWS Academy Learner Lab (uses the built-in `LabRole`) |

## Architecture

```
 git push ─► GitHub ──webhook──► Jenkins (EC2, port 8080)
                                   │ 1. Checkout
                                   │ 2. docker build  (tag = build number)
                                   │ 3. docker push ─────► Docker Hub
                                   │ 4. kubectl apply ───► Amazon EKS
                                   ▼
                     Deployment "survey-app" (3 pods, nginx + site)
                                   ▲
                Service "survey-service" (type LoadBalancer → AWS ELB)
                                   ▲
                          Browser (public AWS URL)
```

## Repository layout

| Path | Purpose |
|---|---|
| `web/` | Homework 1 site: `index.html`, `survey.html`, `error.html`, `profile.jpg` |
| `Dockerfile` | Builds an `nginx:1.27-alpine` image that serves `web/` on port 80 |
| `nginx.conf` | Site config: custom 404 page and `/healthz` health endpoint |
| `.dockerignore`, `.gitignore` | Keep build context small and secrets out of Git |
| `k8s/deployment.yaml` | Deployment: 3 replicas, rolling updates, resource limits, readiness/liveness probes |
| `k8s/service.yaml` | Service of type LoadBalancer (public AWS URL) |
| `k8s/jenkins-access.yaml` | ServiceAccount + token + RoleBinding (`edit` in `default`) used by Jenkins to deploy |
| `Jenkinsfile` | Pipeline: Checkout → Build → Push to Docker Hub → Deploy to Kubernetes |
| `scripts/setup-jenkins-ec2.sh` | Installs Java, Jenkins, Docker, kubectl and AWS CLI on the Jenkins EC2 (Ubuntu) |

## Quick start

Prerequisites: Docker Desktop, AWS CLI v2, kubectl, a Docker Hub account, a GitHub account, and an AWS Academy Learner Lab session (`us-east-1`).

### 1. Build and push the image
```bash
docker build -t swe645-survey .
docker run -d -p 8080:80 --name test swe645-survey     # test at http://localhost:8080
docker rm -f test
docker login -u mkharote
docker buildx build --platform linux/amd64 \
  -t mkharote/swe645-survey:v2 -t mkharote/swe645-survey:latest --push .
```
`--platform linux/amd64` is needed when building on Apple Silicon, because the EKS nodes are x86-64.

### 2. Create the EKS cluster (Learner Lab, LabRole)
```bash
ACCT=$(aws sts get-caller-identity --query Account --output text)
ROLE="arn:aws:iam::${ACCT}:role/LabRole"
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC \
  Name=availability-zone,Values=us-east-1a,us-east-1b,us-east-1c,us-east-1d,us-east-1f \
  --query 'Subnets[].SubnetId' --output text | tr '\t' ',')

aws eks create-cluster --name swe645-cluster --role-arn "$ROLE" \
  --resources-vpc-config subnetIds=$SUBNETS,endpointPublicAccess=true,endpointPrivateAccess=true \
  --access-config authenticationMode=API_AND_CONFIG_MAP,bootstrapClusterCreatorAdminPermissions=true
aws eks wait cluster-active --name swe645-cluster

aws eks create-nodegroup --cluster-name swe645-cluster --nodegroup-name swe645-nodes \
  --node-role "$ROLE" --subnets $(echo $SUBNETS | tr ',' ' ') \
  --instance-types t3.medium --ami-type AL2023_x86_64_STANDARD \
  --scaling-config minSize=2,maxSize=3,desiredSize=2
aws eks wait nodegroup-active --cluster-name swe645-cluster --nodegroup-name swe645-nodes

aws eks update-kubeconfig --region us-east-1 --name swe645-cluster
kubectl get nodes
```
`us-east-1e` is excluded because EKS does not support control-plane subnets in that zone.

### 3. Deploy with kubectl
```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/survey-app
kubectl get deployments,pods,svc -o wide
echo "http://$(kubectl get svc survey-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```
Resiliency check: `kubectl delete pod <pod-name>` and then `kubectl get pods`. A replacement pod is created automatically.

### 4. Jenkins server
1. Launch an EC2 instance: Ubuntu 24.04, t3.medium, 25 GB disk. Security group: allow inbound TCP 22 and TCP **8080**.
2. On the instance: `git clone https://github.com/Madhusudan01/swe645-hw2.git && bash swe645-hw2/scripts/setup-jenkins-ec2.sh`
3. Open `http://<EC2-IP>:8080`, unlock with the initial admin password, install suggested plugins, and create an admin user.
4. Allow Jenkins to reach the Kubernetes API:
   ```bash
   CLUSTER_SG=$(aws eks describe-cluster --name swe645-cluster --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)
   aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG --protocol tcp --port 443 --source-group <JENKINS_SG_ID>
   ```

### 5. Jenkins credentials
| ID | Kind | Contents |
|---|---|---|
| `dockerhub-creds` | Username with password | Docker Hub username + access token (Read & Write) |
| `eks-kubeconfig` | Secret file | kubeconfig for the `jenkins-deployer` ServiceAccount (see below) |

Create the ServiceAccount kubeconfig on your machine:
```bash
kubectl apply -f k8s/jenkins-access.yaml
TOKEN=$(kubectl get secret jenkins-deployer-token -o jsonpath='{.data.token}' | base64 --decode)
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
cat > kubeconfig-jenkins <<EOF
apiVersion: v1
kind: Config
clusters:
- name: swe645-cluster
  cluster: {server: $SERVER, certificate-authority-data: $CA}
users:
- name: jenkins-deployer
  user: {token: $TOKEN}
contexts:
- name: jenkins
  context: {cluster: swe645-cluster, user: jenkins-deployer, namespace: default}
current-context: jenkins
EOF
```
Upload `kubeconfig-jenkins` as the `eks-kubeconfig` secret file, and do **not** commit it. With its own service account, the pipeline keeps working across Learner Lab restarts and never uses the temporary AWS keys.

### 6. Pipeline job and webhook
- Jenkins → New Item → **Pipeline** `swe645-hw2` → check *GitHub hook trigger for GITScm polling* → *Pipeline script from SCM*, Git, repository URL above, branch `*/main`, script path `Jenkinsfile`.
- GitHub → Settings → Webhooks → Payload URL `http://<EC2-IP>:8080/github-webhook/`, content type `application/json`, push events.
- Any `git push` to `main` now builds, pushes and redeploys automatically. Check with `kubectl describe deployment survey-app | grep Image`.

## Learner Lab notes and troubleshooting
| Symptom | Cause / fix |
|---|---|
| `ExpiredToken`, `AuthFailure`, `SignatureDoesNotMatch` | Lab keys change every session. Copy fresh values from **AWS Details → AWS CLI**. |
| Pods `Pending`, `kubectl get nodes` empty after a lab restart | Nodes were stopped. Scale the node group to 0, then back to 2. |
| GitHub webhook fails after a lab restart | Jenkins public IP changed. Update the webhook Payload URL. |
| Jenkins deploy: `dial tcp 172.31.x.x:443: i/o timeout` | Cluster security group must allow TCP 443 from the Jenkins security group. |
| Pods `CrashLoopBackOff` / `exec format error` | Image built for ARM. Rebuild with `--platform linux/amd64`. |
| Jenkins `docker: permission denied` | `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins` |
| Jenkins apt `NO_PUBKEY` | Use the current signing key `jenkins.io-2026.key` (already in the setup script). |

## Cleanup
```bash
kubectl delete -f k8s/
aws eks delete-nodegroup --cluster-name swe645-cluster --nodegroup-name swe645-nodes
aws eks wait nodegroup-deleted --cluster-name swe645-cluster --nodegroup-name swe645-nodes
aws eks delete-cluster --name swe645-cluster
```
Then terminate the `jenkins-server` EC2 instance.
