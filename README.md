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

This is a namespace-scoped `Role`, not a `ClusterRole`.

Verify:

```powershell
.\scripts\verify-jenkins-rbac.ps1
```

Expected important results:

```text
create pods namespace=jenkins-agents -> yes
create pods namespace=default        -> no
```

The RBAC permissions follow the resources used by the official Jenkins
Kubernetes plugin example: Pods, Pod exec/logs, events, and secret reads in
the agent namespace.

---

# 8. Create Jenkins Kubernetes kubeconfig

Jenkins is outside Kubernetes, so it needs a credential to call:

```text
https://192.168.100.210:6443
```

For the private lab, run:

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
2. creates a ServiceAccount token Secret for the lab
3. obtains the Kubernetes CA and token
4. writes a kubeconfig without printing the token
5. verifies namespace-only Pod creation
```

The generated kubeconfig is ignored by Git.

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

There are two separate paths.

## Jenkins -> K3s API

```text
Jenkins VM 192.168.100.220
    -> TCP 6443
K3s API 192.168.100.210
```

From the Jenkins VM, a basic network check is:

```bash
curl -k https://192.168.100.210:6443/version
```

The Jenkins plugin `Test Connection` in the next step is the authenticated
check.

## Agent Pod -> Jenkins

```text
Kubernetes Pod
    -> HTTP/WebSocket 8080
Jenkins VM 192.168.100.220
```

Run:

```powershell
.\scripts\verify-jenkins-agent-connectivity.ps1
```

It creates a temporary curl Pod, calls:

```text
http://192.168.100.220:8080/jenkins/login
```

and removes the Pod afterward.

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

Create it in the target namespace:

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

For multiple real namespaces, run it once per namespace, for example:

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

# 34. Troubleshooting: Jenkins cannot connect to K3s

From Jenkins VM:

```bash
curl -k https://192.168.100.210:6443/version
```

From Windows:

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

Run:

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

Recreate safely if required:

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
