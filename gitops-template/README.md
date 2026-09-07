# Separate GitOps Repository Template

Copy `apps/` into a separate Git repository, for example `ncim-gitops`.
Jenkins updates only the immutable image reference. Argo CD performs the
Kubernetes deployment.

The sample uses one `demo` namespace for simplicity. In a real environment you
can map `dev`, `qa`, `preprod`, and `prod` overlays to separate namespaces or
clusters.

Because OCIR is normally private, create `ocir-pull-secret` in every target
namespace before Argo CD deploys the application. The root repository includes
`scripts/create-ocir-pull-secret.ps1` for the lab.
