#!/usr/bin/env bash
# Run on the CONNECTED side. Downloads everything that is not a container image:
#   - Cilium 1.20.5 Helm chart (OCI, signed)
#   - cilium CLI v0.20.3  (status, connectivity test, bgp peers)
#   - hubble CLI v1.20.4
#   - helm v3 (to render the chart on the bastion)
# Then carry ./cilium-packages/ across the gap together with the oc-mirror archive.
set -euo pipefail

CILIUM_VERSION=1.20.5
CILIUM_CLI_VERSION=v0.20.3
HUBBLE_VERSION=v1.20.4
HELM_VERSION=${HELM_VERSION:-v3.19.0}   # any helm >= 3.8 with OCI support works
ARCH=amd64
OUT=./cilium-packages
mkdir -p "$OUT" && cd "$OUT"

# 1) Helm (needed for steps 2 and 5)
curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz.sha256sum"
sha256sum -c "helm-${HELM_VERSION}-linux-${ARCH}.tar.gz.sha256sum"
tar xzf "helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" "linux-${ARCH}/helm" --strip-components=1
HELM=./helm

# 2) Cilium Helm chart -> cilium-1.20.5.tgz
"$HELM" pull oci://quay.io/cilium/charts/cilium --version "$CILIUM_VERSION"
# optional signature check (needs cosign):
# cosign verify --certificate-identity-regexp='https://github.com/cilium/cilium/.*' \
#   --certificate-oidc-issuer=https://token.actions.githubusercontent.com quay.io/cilium/charts/cilium:${CILIUM_VERSION}

# 3) cilium CLI
curl -fsSLO "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${ARCH}.tar.gz"
curl -fsSLO "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${ARCH}.tar.gz.sha256sum"
sha256sum -c "cilium-linux-${ARCH}.tar.gz.sha256sum"

# 4) hubble CLI
curl -fsSLO "https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-${ARCH}.tar.gz"
curl -fsSLO "https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-${ARCH}.tar.gz.sha256sum"
sha256sum -c "hubble-linux-${ARCH}.tar.gz.sha256sum"

# 5) Print every image the chart renders with OUR values, then compare it with the imageset
#    (REGISTRY placeholder left as-is, so the upstream paths are easy to read).
if [[ -f ../cilium-values-ocp422.yaml ]]; then
  "$HELM" template cilium "./cilium-${CILIUM_VERSION}.tgz" --namespace cilium --kube-version 1.35.0 \
    -f ../cilium-values-ocp422.yaml | grep -hE '^[[:space:]]*(- )?image:' | sed 's/.*image: *//; s/"//g' | sort -u \
    | tee rendered-images.txt
fi

ls -l
echo "Done. Copy $(pwd) to the disconnected bastion."
