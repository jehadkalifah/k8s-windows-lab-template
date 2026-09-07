# GitOps Repository Template

This folder is an example only. In real use, copy its contents into a separate Git repository such as `ncim-gitops`.

Jenkins updates only the image reference. Argo CD watches that repository and performs the Kubernetes deployment. Jenkins does not run `kubectl apply`.
