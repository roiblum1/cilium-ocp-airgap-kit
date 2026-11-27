# Cilium documentation (offline copy)

`cilium-1.20.5/` is the `Documentation/` tree from [cilium/cilium](https://github.com/cilium/cilium) at tag `v1.20.5` (commit `150121410c147fad575ac5dcbce6de923be69042`), the same version this kit installs. It is copied unchanged, except that the `_api` symlink (pointing to `../api` in the Cilium source tree) is left out.

The files are Sphinx reStructuredText sources. GitHub renders them, though Sphinx-only directives show up as raw text. The online version is at https://docs.cilium.io/en/v1.20/.

Useful pages for this kit:

| Topic | Path |
|---|---|
| OpenShift install | `cilium-1.20.5/installation/k8s-install-openshift-okd.rst`, `requirements-openshift.rst` |
| Helm install | `cilium-1.20.5/installation/k8s-install-helm.rst` |
| Kube-proxy replacement | `cilium-1.20.5/network/kubernetes/kubeproxy-free.rst` |
| L2 announcements | `cilium-1.20.5/network/l2-announcements.rst` |
| LB IPAM | `cilium-1.20.5/network/lb-ipam.rst` |
| BGP control plane | `cilium-1.20.5/network/bgp-control-plane/` |
| Hubble | `cilium-1.20.5/observability/` |
| Helm values reference | `cilium-1.20.5/helm-values.rst` |

Licensed under Apache License 2.0 by the Cilium Authors; see `cilium-1.20.5/LICENSE`.
