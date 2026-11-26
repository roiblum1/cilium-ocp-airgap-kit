#!/usr/bin/env bash
# Run on the DISCONNECTED bastion, after `openshift-install create manifests --dir $INSTALL_DIR`
# and before `create ignition-configs`.
#
# Writes Cilium 1.20.5 into $INSTALL_DIR/manifests as day-0 manifests:
#   cluster-network-03-config.yml       CNO: deployKubeProxy=false (Cilium replaces kube-proxy)
#   cluster-network-05-cilium-ns.yaml   namespace "cilium" (run-level 0 + privileged PSA)
#   cluster-network-06-cilium-NNNN.yaml one object per file (helm template output)
#
# Usage:
#   REGISTRY=registry.lab.local:8443/mirror API_INT=api-int.lab.example.com \
#     ./render-cilium-manifests.sh ./install-dir
set -euo pipefail

INSTALL_DIR=${1:?usage: $0 <install-dir>}
REGISTRY=${REGISTRY:?set REGISTRY (mirror prefix holding cilium/*)}
API_INT=${API_INT:?set API_INT (api-int.<cluster>.<baseDomain>)}
PKG=${PKG:-./cilium-packages}
CHART=${CHART:-$PKG/cilium-1.20.5.tgz}
HELM=${HELM:-$PKG/helm}
VALUES=${VALUES:-./cilium-values-ocp422.yaml}
KUBE_VERSION=${KUBE_VERSION:-1.35.0}   # Kubernetes level of OpenShift 4.22
M="$INSTALL_DIR/manifests"

[[ -d "$M" ]] || { echo "run 'openshift-install create manifests' first"; exit 1; }
grep -q 'networkType: Cilium' "$M/cluster-network-02-config.yml" \
  || { echo "install-config.yaml must have networking.networkType: Cilium"; exit 1; }
[[ -e "$M/cluster-network-03-config.yml" ]] \
  && { echo "$M/cluster-network-03-config.yml exists — merge 'deployKubeProxy: false' into it by hand"; exit 1; }

# 1) CNO: no standalone kube-proxy for a third-party plugin (Cilium KPR takes over)
cat > "$M/cluster-network-03-config.yml" <<'EOF'
apiVersion: operator.openshift.io/v1
kind: Network
metadata:
  name: cluster
spec:
  deployKubeProxy: false
EOF

# 2) Namespace — run-level 0 skips SCC admission, same as the vendor OLM packaging
cat > "$M/cluster-network-05-cilium-ns.yaml" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: cilium
  annotations:
    openshift.io/node-selector: ""
  labels:
    name: cilium
    openshift.io/run-level: "0"
    openshift.io/cluster-monitoring: "true"
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
    security.openshift.io/scc.podSecurityLabelSync: "false"
EOF

# 3) Render the chart with the mirror + api-int filled in
TMP=$(mktemp -d)
sed -e "s#REGISTRY#${REGISTRY}#g" -e "s#API_INT_HOST#${API_INT}#g" "$VALUES" > "$TMP/values.yaml"
"$HELM" template cilium "$CHART" --namespace cilium --kube-version "$KUBE_VERSION" \
  -f "$TMP/values.yaml" > "$TMP/cilium.yaml"

# 4) Split into one object per file; skip empty/comment-only documents
awk -v dir="$M" '
  function flush() {
    if (buf ~ /(^|\n)kind:[ \t]*[A-Za-z]/) {
      n++; f = sprintf("%s/cluster-network-06-cilium-%04d.yaml", dir, n)
      printf "%s", buf > f; close(f)
    }
    buf = ""
  }
  /^---/ { flush(); next }
  { buf = buf $0 "\n" }
  END { flush(); print n " Cilium manifests written" }' "$TMP/cilium.yaml"

# 5) Show what the nodes will pull — every line must start with $REGISTRY
echo "--- images referenced:"
grep -hE '^[[:space:]]*(- )?image:' "$M"/cluster-network-06-cilium-*.yaml | sed 's/.*image: *//; s/"//g' | sort -u
rm -rf "$TMP"
