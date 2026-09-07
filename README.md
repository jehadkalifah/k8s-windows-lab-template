# Jenkins + OCIR + Argo CD CI/CD Sample

Standalone CI/CD example for an already-prepared Jenkins and Kubernetes environment.

This repository contains **no environment provisioning**. It does not install Vagrant, K3s, Jenkins, Argo CD, Istio, MetalLB, Vault, Reloader, SonarQube, Trivy, or OCI infrastructure.

## Flow

```text
Developer
   -> Git
   -> Jenkins
      -> restore/build/test
      -> SonarQube + Quality Gate
      -> Docker build
      -> Trivy
      -> push immutable image to OCIR
      -> update GitOps repository
   -> Argo CD
   -> Kubernetes RollingUpdate
```

Jenkins does **not** run `kubectl apply`.

## Sample app

ASP.NET Core on `.NET 10` with:

```text
GET /
GET /api/hello
GET /healthz
```

## Jenkins branch mapping

```text
development -> dev
qa          -> qa
preprod     -> preprod
main        -> prod
other       -> CI only
```

## Image format

```text
jed.ocir.io/<namespace>/sample-api:<branch>-<build-number>-<git-sha>
```

Example:

```text
jed.ocir.io/mynamespace/sample-api:development-152-a8f31c2
```

Do not deploy `latest`.

## Jenkins agent expected

The Jenkinsfile expects an existing agent labelled:

```text
docker-dotnet
```

with:

```text
Git
.NET 10 SDK
Docker CLI + engine access
Trivy
Python 3
```

No agent installation is included.

## Jenkins credentials

OCIR:

```text
ID: ocir-credentials
Type: Username with password
Username: <tenancy-namespace>/<username>
Password: OCI auth token
```

For a non-default OCI identity domain, the username can include the domain.

GitOps repository:

```text
ID: gitops-credentials
Type: Username with password
```

Set these values in/for the Jenkins build:

```text
OCIR_NAMESPACE = CHANGE_ME
GITOPS_REPO_URL = https://...
```

The Jeddah OCIR endpoint used here is:

```text
jed.ocir.io
```

## SonarQube

Jenkins server config name expected:

```text
SonarQubeServer
```

Pinned local scanner:

```text
dotnet-sonarscanner 11.3.0
```

Pipeline order:

```text
Sonar begin
Build
Unit tests
Sonar end
Quality Gate
```

For first plumbing tests you can set:

```text
ENABLE_SONAR=false
```

## Trivy

The pipeline scans the built image for:

```text
HIGH,CRITICAL
```

and fails on fixed findings. Disable temporarily with:

```text
ENABLE_TRIVY=false
```

## OCIR push

With:

```text
PUSH_IMAGE=true
```

Jenkins logs in using Jenkins Credentials and pushes the immutable image.

## GitOps

`gitops-template/` is included only as a template. In real use, move it into a separate repository:

```text
ncim-gitops/
└── apps/
    └── sample-api/
        ├── base/
        └── overlays/
            ├── dev/
            ├── qa/
            ├── preprod/
            └── prod/
```

Jenkins updates:

```text
apps/sample-api/overlays/<environment>/kustomization.yaml
```

with the new immutable image and pushes the Git commit. Argo CD then handles deployment.

## Argo CD

Example Application:

```text
argocd-app-examples/sample-api-dev.yaml
```

Change its `repoURL` to your real GitOps repository.

## Kubernetes rollout

The example Deployment uses:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

plus readiness/liveness checks on `/healthz` and:

```yaml
reloader.stakater.com/auto: "true"
```

## First Jenkins test

Start with:

```text
ENABLE_SONAR=false
ENABLE_TRIVY=false
PUSH_IMAGE=false
GITOPS_REPO_URL=
```

This validates checkout, restore, build, tests, and Docker build without pushing or deploying.

Recommended enablement order:

```text
1. Build + unit tests
2. SonarQube
3. Docker build
4. Trivy
5. OCIR push
6. Separate GitOps repository
7. Jenkins GitOps update
8. Argo CD automatic sync
9. Production approval/promotion
```

## Responsibility boundary

```text
Jenkins -> CI, artifact, scan, OCIR, GitOps commit
Argo CD -> CD, sync, drift correction, Kubernetes rollout
```
