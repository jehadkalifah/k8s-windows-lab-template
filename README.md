# Jenkins + Kubernetes Agents + BuildKit + OCIR + Argo CD CI/CD

A complete CI/CD example for the lab where the platform is already prepared.

This repository **does not install** Vagrant, K3s, Jenkins, Argo CD, Istio,
MetalLB, Vault, Longhorn, Reloader, SonarQube, Trivy, or OCI infrastructure.
It starts at the point where Jenkins and Kubernetes already exist and connects
all CI/CD pieces from beginning to end.

## Lab topology used by this repository

```text
K3s API:              https://192.168.100.210:6443
Jenkins VM:           192.168.100.220
Jenkins direct URL:   http://192.168.100.220:8080/jenkins/
Public Gateway VIP:   192.168.100.240
OCIR endpoint:        jed.ocir.io
Jenkins agent ns:     jenkins-agents
```

---

# 1. Final design

```text
Developer
   |
   v
Application Git repository
   |
   | webhook / Multibranch scan
   v
Jenkins Controller VM
192.168.100.220
   |
   | Jenkins Kubernetes plugin
   | HTTPS 6443
   v
K3s API
192.168.100.210
   |
   v
Temporary Jenkins agent Pod
namespace: jenkins-agents
   |
   +-- jnlp       Jenkins connection
   +-- git        checkout + GitOps commit
   +-- dotnet     restore/build/test/Sonar
   +-- buildkit   rootless container-image build
   +-- trivy      vulnerability scan
   |
   +-----------------------> OCIR
   |                         jed.ocir.io
   |
   v
GitOps repository
   |
   v
Argo CD
   |
   v
Kubernetes
   |
   +-- RollingUpdate
   +-- Istio Gateway API
   +-- Reloader
```

Jenkins does **not** deploy the application with `kubectl apply` and the
Jenkins controller VM does **not** need Docker, .NET, Trivy, or build tools.

---

# 2. Why this uses rootless BuildKit

Do not expose a K3s node runtime to build Pods by mounting:

```text
/var/run/docker.sock
```

and do not use privileged Docker-in-Docker unless you have a specific reason.

This repository uses:

```text
moby/buildkit:v0.30.0-rootless
```

BuildKit can build the Dockerfile and push the resulting image directly to
OCIR without a Docker daemon.

```text
Dockerfile
   |
   v
rootless BuildKit in ephemeral agent Pod
   |
   +-- PUSH_IMAGE=false -> temporary OCI tar
   |
   +-- PUSH_IMAGE=true  -> direct push to jed.ocir.io
```

The agent Pod has:

```yaml
automountServiceAccountToken: false
```

so the build itself does not receive Kubernetes API credentials.

---

# 3. Repository layout

```text
.
├── Jenkinsfile
├── Dockerfile
├── README.md
├── SampleCiCd.slnx
│
├── kubernetes/
│   └── jenkins-agents/
│       ├── namespace-rbac.yaml
│       └── lab-token-secret.yaml
│
├── jenkins/
│   ├── pipelines/
│   │   ├── 01-kubernetes-agent-smoke.Jenkinsfile
│   │   └── 02-buildkit-ocir-smoke.Jenkinsfile
│   └── pod-templates/
│       └── ci-buildkit.yaml
│
├── scripts/
│   ├── bootstrap-jenkins-k8s-access.ps1
│   ├── verify-jenkins-rbac.ps1
│   ├── verify-jenkins-agent-connectivity.ps1
│   ├── create-ocir-pull-secret.ps1
│   ├── git-askpass.sh
│   └── update-gitops.sh
│
├── src/SampleApi/
├── tests/SampleApi.Tests/
├── gitops-template/
└── argocd-app-examples/
```

---

# 4. Versions used by the example

Verified for this sample:

```text
Jenkins Kubernetes plugin: 4547.v52f3080db_8cd
BuildKit:                  v0.30.0-rootless
Trivy:                     0.74.0
.NET:                      10.0
SonarScanner for .NET:     11.3.0
```

The Kubernetes plugin currently requires Jenkins 2.516.3 or newer; the lab
controller is Jenkins 2.568.3.

---

# 5. Prerequisites

Before configuring CI/CD, verify:

```text
[ ] Jenkins VM is running
[ ] Jenkins opens at http://192.168.100.220:8080/jenkins/
[ ] K3s nodes are Ready
[ ] Windows kubectl reaches the K3s cluster
[ ] Jenkins VM can reach 192.168.100.210:6443
[ ] K3s Pods can reach 192.168.100.220:8080
[ ] OCIR repository and IAM permissions are ready
[ ] Application source repository exists
```

Check cluster:

```powershell
kubectl get nodes -o wide
```

---

## Manual commands versus helper scripts

For bootstrap and credential tasks, this README intentionally shows **both**:

```text
Option A — Manual commands
  Understand and execute every Kubernetes/Jenkins step yourself.

Option B — Repository helper script
  Perform the same operation faster and repeatably.
```

The helper scripts are not required. They remain in the repository as an
automation option after you understand or validate the manual procedure.

---

# 6. Install Jenkins Kubernetes plugin

In Jenkins:

```text
Manage Jenkins
  -> Plugins
  -> Available plugins
  -> Kubernetes
  -> Install
```

The Kubernetes plugin creates ephemeral Jenkins agents as Pods.

## Controller isolation

Recommended:

```text
Manage Jenkins
  -> Nodes
  -> Built-In Node
  -> Configure
  -> Number of executors = 0
```

Builds will then run only on proper agents.

---

# 7. Create namespace and Jenkins controller RBAC

You have **two supported options** for this step:

```text
Option A -> run the Kubernetes commands/manifests manually
Option B -> use the repository helper script
```

Both options create the same namespace-scoped Jenkins controller permissions.

## Option A — Manual

Run from PowerShell in this repository:

```powershell
kubectl apply -f .\kubernetes\jenkins-agents\namespace-rbac.yaml
```

It creates:

```text
Namespace:      jenkins-agents
ServiceAccount: jenkins-agent-manager
Role:           jenkins-agent-manager
RoleBinding:    jenkins-agent-manager
```

This is intentionally a namespace-scoped `Role`, **not** a `ClusterRole`.

Verify manually:

```powershell
kubectl auth can-i create pods \
  --as=system:serviceaccount:jenkins-agents:jenkins-agent-manager \
  -n jenkins-agents

kubectl auth can-i create pods \
  --as=system:serviceaccount:jenkins-agents:jenkins-agent-manager \
  -n default
```

Expected:

```text
create pods namespace=jenkins-agents -> yes
create pods namespace=default        -> no
```

You can also verify the other permissions used by the Jenkins Kubernetes
plugin:

```powershell
kubectl auth can-i get pods \
  --as=system:serviceaccount:jenkins-agents:jenkins-agent-manager \
  -n jenkins-agents

kubectl auth can-i create pods/exec \
  --as=system:serviceaccount:jenkins-agents:jenkins-agent-manager \
  -n jenkins-agents

kubectl auth can-i get pods/log \
  --as=system:serviceaccount:jenkins-agents:jenkins-agent-manager \
  -n jenkins-agents
```

Expected:

```text
yes
yes
yes
```

## Option B — Repository helper

The repository includes:

```powershell
.\scripts\verify-jenkins-rbac.ps1
```

This performs the same important permission checks automatically.

If you use the combined bootstrap helper in the next section:

```powershell
.\scripts\bootstrap-jenkins-k8s-access.ps1
```

it also applies `namespace-rbac.yaml` before creating the Jenkins kubeconfig,
so you do not need to apply the manifest separately.

The RBAC permissions are limited to the resources required for Jenkins agent
Pod lifecycle operations in the `jenkins-agents` namespace: Pods, Pod
exec/logs, events, and Secret reads.

---

# 8. Create Jenkins Kubernetes kubeconfig

Jenkins is outside Kubernetes, so it needs a credential to call:

```text
https://192.168.100.210:6443
```

Again, you have two supported options.

## Option A — Create it manually

### 8.1 Ensure the RBAC exists

If you did not already complete section 7:

```powershell
kubectl apply -f .\kubernetes\jenkins-agents\namespace-rbac.yaml
```

### 8.2 Create the lab ServiceAccount token Secret

Apply the repository manifest:

```powershell
kubectl apply -f .\kubernetes\jenkins-agents\lab-token-secret.yaml
```

It creates:

```text
Namespace: jenkins-agents
Secret:    jenkins-agent-manager-token
Type:      kubernetes.io/service-account-token
```

Confirm Kubernetes populated it:

```powershell
kubectl -n jenkins-agents get secret jenkins-agent-manager-token
```

### 8.3 Read the token and CA into PowerShell variables

Do not print the token.

```powershell
$TokenB64 = kubectl -n jenkins-agents get secret jenkins-agent-manager-token `
  -o jsonpath='{.data.token}'

$CaB64 = kubectl -n jenkins-agents get secret jenkins-agent-manager-token `
  -o jsonpath='{.data.ca\.crt}'

$Token = [Text.Encoding]::UTF8.GetString(
  [Convert]::FromBase64String($TokenB64)
)
```

Confirm the variables are populated without displaying their contents:

```powershell
$Token.Length
$CaB64.Length
```

Both should be greater than zero.

### 8.4 Write the Jenkins kubeconfig manually

From the repository root:

```powershell
$KubernetesServer = "https://192.168.100.210:6443"
$OutputFile = ".\jenkins-agent-manager.kubeconfig"

$KubeConfig = @"
apiVersion: v1
kind: Config
clusters:
  - name: k3s-lab
    cluster:
      server: $KubernetesServer
      certificate-authority-data: $CaB64
contexts:
  - name: jenkins-agent-manager@k3s-lab
    context:
      cluster: k3s-lab
      namespace: jenkins-agents
      user: jenkins-agent-manager
current-context: jenkins-agent-manager@k3s-lab
users:
  - name: jenkins-agent-manager
    user:
      token: $Token
"@

[IO.File]::WriteAllText(
  (Join-Path (Get-Location) "jenkins-agent-manager.kubeconfig"),
  $KubeConfig,
  (New-Object Text.UTF8Encoding($false))
)
```

The generated kubeconfig is ignored by Git.

### 8.5 Verify the generated kubeconfig

```powershell
kubectl --kubeconfig=.\jenkins-agent-manager.kubeconfig `
  auth can-i create pods -n jenkins-agents

kubectl --kubeconfig=.\jenkins-agent-manager.kubeconfig `
  auth can-i create pods -n default
```

Expected:

```text
yes
no
```

Also verify that the credential can actually reach the cluster:

```powershell
kubectl --kubeconfig=.\jenkins-agent-manager.kubeconfig `
  get pods -n jenkins-agents
```

After the file has been uploaded to Jenkins Credentials, clear the plaintext
token variables from the current PowerShell session:

```powershell
$Token = $null
$TokenB64 = $null
$CaB64 = $null
```

## Option B — Repository helper

For the private lab, the repository can perform the entire process:

```powershell
.\scripts\bootstrap-jenkins-k8s-access.ps1
```

Defaults:

```text
Kubernetes API: https://192.168.100.210:6443
Output file:    jenkins-agent-manager.kubeconfig
```

The script:

```text
1. applies the namespace/RBAC
2. creates the ServiceAccount token Secret for the lab
3. obtains the Kubernetes CA and token
4. writes the kubeconfig without printing the token
5. verifies namespace-only Pod creation
```

To use another Kubernetes API address or output name:

```powershell
.\scripts\bootstrap-jenkins-k8s-access.ps1 `
  -KubernetesServer "https://192.168.100.210:6443" `
  -OutputFile "jenkins-agent-manager.kubeconfig"
```

### Security note

The manually created ServiceAccount token is intentionally a **lab-friendly
persistent credential**. For production, prefer a short-lived or rotated
credential mechanism supported by your Kubernetes platform and Jenkins.

---

# 9. Add Kubernetes credential to Jenkins

In Jenkins:

```text
Manage Jenkins
  -> Credentials
  -> System
  -> Global credentials
  -> Add Credentials
```

Use:

```text
Kind: Secret file
File: jenkins-agent-manager.kubeconfig
ID:   k3s-jenkins-agents-kubeconfig
```

Never put the token directly inside a Jenkinsfile.

---

# 10. Verify networking in both directions

There are two separate network paths and both must work.

## Jenkins -> K3s API

```text
Jenkins VM 192.168.100.220
    -> TCP 6443
K3s API 192.168.100.210
```

### Option A — Manual

From the Jenkins VM:

```bash
curl -k https://192.168.100.210:6443/version
```

That verifies basic TCP/TLS reachability. After section 9, you can also test
the generated credential from any machine that has the kubeconfig:

```powershell
kubectl --kubeconfig=.\jenkins-agent-manager.kubeconfig `
  get pods -n jenkins-agents
```

The Jenkins Kubernetes Cloud `Test Connection` in the next section is the
final authenticated check from Jenkins itself.

### Option B — Helper/GUI checks

The bootstrap script already verifies that its generated kubeconfig can create
Pods only in `jenkins-agents`:

```powershell
.\scripts\bootstrap-jenkins-k8s-access.ps1
```

Then use Jenkins:

```text
Manage Jenkins -> Clouds -> Kubernetes -> Test Connection
```

## Agent Pod -> Jenkins

```text
Kubernetes Pod
    -> HTTP/WebSocket 8080
Jenkins VM 192.168.100.220
```

### Option A — Manual connectivity test

Create a temporary curl Pod:

```powershell
kubectl -n jenkins-agents run jenkins-connect-test `
  --image=curlimages/curl:8.16.0 `
  --restart=Never `
  --command -- sh -c `
  "curl -fsS -o /dev/null -w '%{http_code}' 'http://192.168.100.220:8080/jenkins/login'"
```

Wait for completion:

```powershell
kubectl -n jenkins-agents wait `
  --for=jsonpath='{.status.phase}'=Succeeded `
  pod/jenkins-connect-test `
  --timeout=90s
```

Read the HTTP status:

```powershell
kubectl -n jenkins-agents logs jenkins-connect-test
```

An HTTP status such as `200`, `301`, `302`, or `403` proves that the Pod can
reach the Jenkins HTTP endpoint.

Delete the temporary Pod:

```powershell
kubectl -n jenkins-agents delete pod jenkins-connect-test
```

### Option B — Repository helper

```powershell
.\scripts\verify-jenkins-agent-connectivity.ps1
```

The script performs the same temporary Pod test against:

```text
http://192.168.100.220:8080/jenkins/login
```

and removes the Pod automatically.

---

# 11. Configure Jenkins Kubernetes Cloud

Go to:

```text
Manage Jenkins
  -> Clouds
  -> New cloud
  -> Kubernetes
```

Use:

```text
Name:
  kubernetes

Kubernetes URL:
  https://192.168.100.210:6443

Kubernetes Namespace:
  jenkins-agents

Credentials:
  k3s-jenkins-agents-kubeconfig

Jenkins URL:
  http://192.168.100.220:8080/jenkins/

WebSocket:
  Enabled
```

Use the Jenkins VM's direct LAN URL for agent traffic instead of routing agent
traffic through the public Gateway VIP.

The Jenkins Kubernetes plugin recommends WebSocket when the Jenkins controller
is outside the cluster because agent communication can use normal HTTP(S)
instead of the separate inbound-agent TCP port.

Click:

```text
Test Connection
```

Do not continue until this succeeds.

Optional settings:

```text
Container cap: 10
Pod retention: Never
Restrict cloud to authorized CI folders: recommended if useful
```

You do not need a permanent static agent Pod template in the Jenkins UI. The
pipeline defines the Pod from repository code.

---

# 12. First smoke test: Jenkins -> Kubernetes agent

Do **not** start with OCIR or SonarQube.

First prove only:

```text
Jenkins
  -> Kubernetes API
  -> temporary agent Pod
  -> pipeline executes
  -> Pod is deleted
```

Use:

```text
jenkins/pipelines/01-kubernetes-agent-smoke.Jenkinsfile
```

Create a temporary Pipeline job and paste that script.

While it runs:

```powershell
kubectl -n jenkins-agents get pods -w
```

The smoke test also checks that the agent Pod does not have this file:

```text
/var/run/secrets/kubernetes.io/serviceaccount/token
```

Do not continue until this works.

---

# 13. Final Jenkins agent Pod

The reusable Pod definition is:

```text
jenkins/pod-templates/ci-buildkit.yaml
```

Containers:

```text
jnlp      Jenkins agent connection; injected by Jenkins plugin
git       source checkout and GitOps Git operations
dotnet    .NET restore/build/test/Sonar
buildkit  rootless Dockerfile build
trivy     image vulnerability scan
```

The explicit containers use UID/GID 1000 to reduce cross-container Jenkins
workspace permission problems.

The BuildKit container uses:

```yaml
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  allowPrivilegeEscalation: false
  seccompProfile:
    type: Unconfined
  appArmorProfile:
    type: Unconfined
```

and:

```text
BUILDKITD_FLAGS=--oci-worker-no-process-sandbox
```

This follows the official rootless BuildKit Kubernetes model. BuildKit itself
documents caveats for `--oci-worker-no-process-sandbox`; it is used because
Kubernetes does not provide the exact system-path unconfined behavior that
rootless BuildKit otherwise uses.

The Pod does **not** use:

```text
privileged: true
/var/run/docker.sock
node containerd socket
```

---

# 14. Create OCIR push credential in Jenkins

Generate an OCI Auth Token for the CI user and give that user/group only the
required Container Registry permissions.

Create this Jenkins credential:

```text
Kind: Username with password
ID:   ocir-credentials
```

Default OCI identity domain username:

```text
<tenancy-namespace>/<username>
```

Non-default identity domain:

```text
<tenancy-namespace>/<domain>/<username>
```

Password:

```text
OCI Auth Token
```

The sample uses:

```text
jed.ocir.io
```

and images look like:

```text
jed.ocir.io/<OCIR_NAMESPACE>/sample-api:<immutable-tag>
```

---

# 15. Second smoke test: BuildKit -> OCIR

Before the full application pipeline, test only:

```text
Jenkins ephemeral agent
  -> rootless BuildKit
  -> OCIR
```

Use:

```text
jenkins/pipelines/02-buildkit-ocir-smoke.Jenkinsfile
```

Set:

```text
OCIR_NAMESPACE=<your real OCI Registry/Object Storage namespace>
```

The smoke pipeline creates a tiny Dockerfile and executes:

```text
buildctl-daemonless.sh build
  --output type=image,name=<OCIR image>,push=true
```

Verify the new `buildkit-smoke` image/tag in OCIR.

---

# 16. How BuildKit authenticates to OCIR

The pipeline temporarily creates:

```text
$WORKSPACE/.docker/config.json
```

from Jenkins Credentials and sets:

```text
DOCKER_CONFIG=$WORKSPACE/.docker
```

BuildKit then pushes directly to OCIR.

The file is deleted after use.

No Docker daemon and no Kubernetes `imagePullSecret` is needed for the **push**
operation itself.

---

# 17. Trivy scanning

The agent Pod uses:

```text
aquasec/trivy:0.74.0
```

The final pipeline scans:

```text
HIGH,CRITICAL
```

with:

```text
--ignore-unfixed
--exit-code 1
```

## When PUSH_IMAGE=false

```text
BuildKit
  -> image.oci.tar
  -> Trivy --input image.oci.tar
```

Nothing is pushed.

## When PUSH_IMAGE=true

```text
BuildKit
  -> OCIR
  -> Trivy scans the pushed immutable image
```

If Trivy fails, the image might remain stored in OCIR, but the pipeline stops
before the GitOps stage so Argo CD does not deploy it.

---

# 18. SonarQube

The repository pins:

```text
dotnet-sonarscanner 11.3.0
```

The Jenkins SonarQube installation name expected by the Jenkinsfile is:

```text
SonarQubeServer
```

Pipeline flow:

```text
Sonar begin
  -> build
  -> unit tests
Sonar end
  -> Quality Gate
```

Initially use:

```text
ENABLE_SONAR=false
```

When enabling it, configure the SonarQube webhook to Jenkins. With this lab's
context path the callback is:

```text
http://192.168.100.220:8080/jenkins/sonarqube-webhook/
```

SonarQube must be able to reach that URL for `waitForQualityGate`.

---

# 19. Full application Jenkinsfile

The repository root `Jenkinsfile` performs:

```text
1. Checkout in git container
2. Build metadata + immutable tag
3. Validate CI parameters
4. dotnet restore
5. Sonar begin                   optional
6. dotnet build
7. unit tests
8. Sonar end                     optional
9. Quality Gate                 optional
10. rootless BuildKit image build
11. Trivy scan                  optional
12. manual production approval  prod only
13. GitOps image-tag update
```

The Jenkins controller VM performs orchestration only.

---

# 20. Image tagging strategy

The Jenkinsfile generates:

```text
<branch>-<build-number>-<git-short-sha>
```

Example:

```text
development-152-a8f31c2
```

Full image:

```text
jed.ocir.io/<namespace>/sample-api:development-152-a8f31c2
```

Do not deploy `latest`.

---

# 21. Branch mapping

```text
development -> dev
qa          -> qa
preprod     -> preprod
main        -> prod
other       -> CI only
```

Feature branches can therefore build and scan without changing a deployment
environment.

---

# 22. Recommended first full pipeline run

Create a Jenkins **Multibranch Pipeline** for the application repository.

Use the root:

```text
Jenkinsfile
```

First run parameters:

```text
ENABLE_SONAR=false
ENABLE_TRIVY=true
PUSH_IMAGE=false
OCIR_NAMESPACE=<your namespace>
GITOPS_REPO_URL=
```

Expected:

```text
Checkout
 -> .NET build/test
 -> BuildKit exports image.oci.tar
 -> Trivy scans the tar
 -> no OCIR push
 -> no GitOps change
 -> agent Pod deleted
```

This isolates the Kubernetes agent + BuildKit + Trivy path first.

---

# 23. Enable real OCIR push

After the BuildKit OCIR smoke test succeeds:

```text
ENABLE_SONAR=false
ENABLE_TRIVY=true
PUSH_IMAGE=true
OCIR_NAMESPACE=<your namespace>
GITOPS_REPO_URL=
```

Expected:

```text
BuildKit -> OCIR -> Trivy
```

No deployment occurs yet because `GITOPS_REPO_URL` is empty.

---

# 24. Create private OCIR pull secret for application Pods

BuildKit pushing to OCIR and Kubernetes pulling from private OCIR are separate
credentials/use cases.

The GitOps Deployment references:

```yaml
imagePullSecrets:
  - name: ocir-pull-secret
```

You can create this Secret manually or with the repository helper.

## Option A — Manual

First ensure the target namespace exists. For the sample:

```powershell
kubectl get namespace demo
```

If it does not exist:

```powershell
kubectl create namespace demo
```

Read the OCIR username and auth token into PowerShell variables instead of
placing the token literally in your command history:

```powershell
$OcirUser = Read-Host "OCIR username (<tenancy-namespace>/[domain/]<username>)"
$SecureOcirToken = Read-Host "OCI auth token" -AsSecureString
$Ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureOcirToken)
$OcirToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Ptr)
```

Create/update the pull Secret:

```powershell
kubectl create secret docker-registry ocir-pull-secret `
  --namespace demo `
  --docker-server=jed.ocir.io `
  --docker-username="$OcirUser" `
  --docker-password="$OcirToken" `
  --dry-run=client `
  -o yaml | kubectl apply -f -
```

Clear the local token variables:

```powershell
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Ptr)
$OcirToken = $null
$SecureOcirToken = $null
```

Verify only the Secret metadata/type; do not print its decoded contents:

```powershell
kubectl -n demo get secret ocir-pull-secret
```

Expected type:

```text
kubernetes.io/dockerconfigjson
```

Repeat the same command for each real namespace by changing `--namespace`.

## Option B — Repository helper

```powershell
.\scripts\create-ocir-pull-secret.ps1
```

Defaults:

```text
Namespace: demo
Registry:  jed.ocir.io
Secret:    ocir-pull-secret
```

The script securely prompts for the OCI username and auth token and does not
write the token to a repository file.

For multiple real namespaces:

```powershell
.\scripts\create-ocir-pull-secret.ps1 -Namespace dev
.\scripts\create-ocir-pull-secret.ps1 -Namespace qa
.\scripts\create-ocir-pull-secret.ps1 -Namespace preprod
.\scripts\create-ocir-pull-secret.ps1 -Namespace prod
```

---

# 25. Create the separate GitOps repository

Do not make Jenkins deploy Kubernetes manifests directly.

Create a separate repository, for example:

```text
ncim-gitops/
└── apps/
    └── sample-api/
        ├── base/
        │   ├── configmap.yaml
        │   ├── deployment.yaml
        │   ├── service.yaml
        │   ├── httproute.yaml
        │   └── kustomization.yaml
        └── overlays/
            ├── dev/
            ├── qa/
            ├── preprod/
            └── prod/
```

Copy:

```text
gitops-template/apps/
```

into that repository.

The sample overlays all target `demo` for simplicity. In a real project you
can change the overlays to separate namespaces/clusters.

---

# 26. Create GitOps credential in Jenkins

Create:

```text
Kind: Username with password
ID:   gitops-credentials
```

Use a user/token that can clone and push only to the intended GitOps repo.

The Jenkinsfile uses:

```text
GIT_ASKPASS
```

so it does not embed the token in the Git repository URL.

---

# 27. Configure Argo CD Applications

Examples are included for:

```text
argocd-app-examples/sample-api-dev.yaml
argocd-app-examples/sample-api-qa.yaml
argocd-app-examples/sample-api-preprod.yaml
argocd-app-examples/sample-api-prod.yaml
```

Change:

```yaml
repoURL: https://git.example.com/platform/ncim-gitops.git
```

and verify each path, for example:

```text
apps/sample-api/overlays/dev
```

The examples use:

```yaml
syncPolicy:
  automated:
    enabled: true
    prune: true
    selfHeal: true
```

Jenkins updates Git; Argo CD updates Kubernetes.

---

# 28. Enable GitOps handoff

Now run Jenkins with:

```text
ENABLE_TRIVY=true
PUSH_IMAGE=true
OCIR_NAMESPACE=<your namespace>
GITOPS_REPO_URL=https://<git-server>/<project>/ncim-gitops.git
```

For `development`:

```text
Jenkins pushes immutable image
 -> Trivy passes
 -> Jenkins updates apps/sample-api/overlays/dev/kustomization.yaml
 -> Jenkins pushes Git commit
 -> Argo CD detects OutOfSync
 -> Argo CD syncs
 -> Kubernetes RollingUpdate
```

---

# 29. Production approval

`main` maps to `prod`.

Before changing the PROD GitOps image, the Jenkinsfile pauses with an `input`
step and requires approval.

Therefore:

```text
build + tests + scan + OCIR push
```

can complete before production promotion is approved.

---

# 30. Kubernetes Deployment rollout

The sample uses:

```yaml
minReadySeconds: 5
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

and:

```text
readiness: /sample-api/healthz
liveness:  /sample-api/healthz
```

This makes the rollout deliberately gradual.

---

# 31. Native `/sample-api` path - no proxy rewrite

The ASP.NET application uses:

```csharp
app.UsePathBase("/sample-api");
```

The HTTPRoute matches:

```text
/sample-api
```

without rewriting.

Request:

```text
http://192.168.100.240/sample-api/api/hello
```

flow:

```text
MetalLB VIP
 -> Istio public-gateway
 -> HTTPRoute
 -> sample-api Service:8080
 -> application /sample-api/api/hello
```

---

# 32. Reloader example

The Deployment is opted in:

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```

and actually consumes:

```text
sample-api-config
```

through `APP_MESSAGE`.

Test:

```powershell
kubectl -n demo patch configmap sample-api-config `
  --type merge `
  -p '{"data":{"APP_MESSAGE":"version-2"}}'
```

Watch:

```powershell
kubectl -n demo get pods -l app=sample-api -w
```

Reloader changes the Pod template and Kubernetes performs the configured
RollingUpdate.

---

# 33. Validate the final deployment

```powershell
kubectl -n demo get deployment,pods,svc
kubectl -n demo get httproute sample-api
kubectl -n demo rollout status deployment/sample-api
```

Application:

```powershell
curl.exe http://192.168.100.240/sample-api/api/hello
```

Health:

```powershell
curl.exe http://192.168.100.240/sample-api/healthz
```

Argo CD should show:

```text
Synced
Healthy
```

---

# Manual-or-script operating rule

For the setup tasks that have helper scripts, the repository now documents two
equivalent workflows:

```text
Manual path
  -> run kubectl/PowerShell commands yourself
  -> useful for learning, debugging and auditing each step

Script path
  -> run the repository helper
  -> useful for repeatability after the manual process is understood
```

The scripts have **not** been removed. The README simply no longer requires
them as the only way to perform the setup.

---

# 34. Troubleshooting: Jenkins cannot connect to K3s

From Jenkins VM:

```bash
curl -k https://192.168.100.210:6443/version
```

From Windows, verify manually:

```powershell
kubectl auth can-i create pods `
  --as=system:serviceaccount:jenkins-agents:jenkins-agent-manager `
  -n jenkins-agents
```

Expected:

```text
yes
```

Or use the helper:

```powershell
.\scripts\verify-jenkins-rbac.ps1
```

Jenkins Cloud must use:

```text
Kubernetes URL: https://192.168.100.210:6443
Namespace:      jenkins-agents
Credentials:    k3s-jenkins-agents-kubeconfig
```

Then use `Test Connection`.

---

# 35. Troubleshooting: agent Pod cannot connect to Jenkins

```powershell
kubectl -n jenkins-agents get pods -o wide
kubectl -n jenkins-agents describe pod <agent-pod>
kubectl -n jenkins-agents logs <agent-pod> -c jnlp
```

For the full manual Pod-to-Jenkins connectivity test, use **section 10,
Option A**.

Or run the helper:

```powershell
.\scripts\verify-jenkins-agent-connectivity.ps1
```

Cloud settings:

```text
Jenkins URL: http://192.168.100.220:8080/jenkins/
WebSocket:   enabled
```

---

# 36. Troubleshooting: rootless BuildKit

The Pod template deliberately uses:

```text
UID/GID 1000
seccomp Unconfined
AppArmor Unconfined
--oci-worker-no-process-sandbox
```

Do not fix a BuildKit issue by immediately mounting `/var/run/docker.sock`.
First compare the generated agent Pod against:

```text
jenkins/pod-templates/ci-buildkit.yaml
```

and check the Pod events/container logs.

---

# 37. Troubleshooting: OCIR unauthorized

Verify:

```text
Endpoint:      jed.ocir.io
Credential ID: ocir-credentials
Username:      <tenancy-namespace>/[domain/]<username>
Password:      OCI Auth Token
```

Also verify OCI IAM policy permits push/manage operations for the intended
registry repository/compartment.

---

# 38. Troubleshooting: application `ImagePullBackOff`

The application Pod needs `ocir-pull-secret` in the **same namespace**.

Check:

```powershell
kubectl -n demo get secret ocir-pull-secret
kubectl -n demo describe pod <sample-api-pod>
```

Recreate it either:

```text
manually -> section 24, Option A
script   -> section 24, Option B
```

Helper command:

```powershell
.\scripts\create-ocir-pull-secret.ps1
```

---

# 39. Troubleshooting: Sonar Quality Gate waits

Verify the Jenkins SonarQube server name is:

```text
SonarQubeServer
```

and SonarQube can call:

```text
http://192.168.100.220:8080/jenkins/sonarqube-webhook/
```

---

# 40. Troubleshooting: Argo CD does not update

Verify Jenkins changed:

```text
apps/sample-api/overlays/<environment>/kustomization.yaml
```

Then verify Argo CD:

```text
repoURL
targetRevision
path
repository credentials
sync status
health status
```

The Jenkins pipeline intentionally does not call `argocd app sync` or
`kubectl apply`.

---

# 41. Complete normal DEV flow

```text
Developer pushes development
        |
        v
Jenkins Multibranch detects change
        |
        v
Jenkins requests ephemeral K3s agent Pod
        |
        v
checkout / restore / build / tests
        |
        v
Sonar + Quality Gate if enabled
        |
        v
rootless BuildKit
        |
        v
immutable image -> jed.ocir.io
        |
        v
Trivy
        |
        v
Jenkins updates DEV GitOps image tag
        |
        v
GitOps commit
        |
        v
Argo CD OutOfSync -> Sync
        |
        v
Kubernetes RollingUpdate
        |
        v
readiness passes
        |
        v
old Pods terminate gradually
        |
        v
Jenkins agent Pod deleted
```

---

# 42. Responsibility boundary

```text
Jenkins controller
  -> orchestrates CI
  -> stores credentials
  -> creates temporary agents

Kubernetes Jenkins agent
  -> checkout
  -> build/test
  -> BuildKit image build
  -> Trivy scan
  -> OCIR push
  -> GitOps commit

OCIR
  -> immutable image registry

GitOps repository
  -> deployment source of truth

Argo CD
  -> Kubernetes deployment/sync

Kubernetes
  -> scheduling/readiness/rollout

Reloader
  -> restart trigger when referenced ConfigMap/Secret changes
```

---

# 43. Recommended implementation order

Follow this exact order:

```text
1. Install Jenkins Kubernetes plugin
2. Set Jenkins built-in executors to 0
3. Apply jenkins-agents namespace/RBAC
4. Generate Jenkins kubeconfig
5. Upload kubeconfig as Jenkins Secret File credential
6. Verify Jenkins -> K3s API networking
7. Verify Pod -> Jenkins networking
8. Configure Jenkins Kubernetes Cloud + WebSocket
9. Run Kubernetes-agent smoke pipeline
10. Create OCIR Jenkins credential
11. Run BuildKit -> OCIR smoke pipeline
12. Run full Jenkinsfile with PUSH_IMAGE=false
13. Enable PUSH_IMAGE=true
14. Verify Trivy remote scan
15. Configure SonarQube + webhook
16. Create OCIR imagePullSecret in deployment namespace
17. Create separate GitOps repository
18. Create GitOps Jenkins credential
19. Configure Argo CD Applications
20. Set GITOPS_REPO_URL and run development
21. Validate Argo CD + RollingUpdate
22. Test Reloader
23. Validate QA/PREPROD
24. Keep production approval for main/prod
```

This order intentionally isolates failures instead of enabling Kubernetes
agents, BuildKit, OCIR, Trivy, SonarQube, GitOps, and Argo CD all at once.

---

# 44. Official references used by this design

```text
Jenkins Kubernetes plugin:
https://plugins.jenkins.io/kubernetes/

Jenkins plugin namespace RBAC example:
https://github.com/jenkinsci/kubernetes-plugin/blob/master/src/main/kubernetes/service-account.yml

BuildKit Kubernetes examples:
https://github.com/moby/buildkit/tree/master/examples/kubernetes

BuildKit rootless example:
https://github.com/moby/buildkit/blob/master/examples/kubernetes/job.rootless.yaml

BuildKit rootless notes:
https://github.com/moby/buildkit/blob/master/docs/rootless.md

Trivy:
https://github.com/aquasecurity/trivy

OCI Container Registry:
https://docs.oracle.com/en-us/iaas/Content/Registry/home.htm
```
