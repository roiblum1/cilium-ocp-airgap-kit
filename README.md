# Cilium 1.20.5 (OSS) on OpenShift 4.22.20 UPI, air-gapped: lab kit

| File | Where | What |
|---|---|---|
| `imageset-cilium-1.20.5.yaml` | connected | oc-mirror v2: 21 images (chart + connectivity test + FRR) |
| `fetch-cilium-packages.sh` | connected | Downloads the Helm chart tgz (OCI), cilium CLI v0.20.3, hubble CLI v1.20.4 and helm, and checks their sha256 |
| `cilium-values-ocp422.yaml` | bastion | One values set for all phases (OpenShift, KPR, L2 + BGP, Hubble, mirror) |
| `render-cilium-manifests.sh` | bastion | Writes the CNO/kube-proxy override, the namespace and the rendered Cilium objects into `manifests/` |
| `phase2-l2-lb-test.yaml` | cluster | IP pool + L2 policy + LoadBalancer Service, no BGP (VM workers) |
| `phase3-bgp-lb-test.yaml` | cluster | BGP cluster config, peer config, advertisement + LoadBalancer Service (bare-metal workers) |
| `docs/cilium-1.20.5/` | anywhere | Offline copy of the upstream Cilium 1.20.5 documentation sources; see `docs/README.md` |

Open-source Cilium has no maintained OpenShift packaging past 1.15 (`isovalent/olm-for-cilium` stops at 1.15.1). This kit renders the upstream chart as day-0 manifests, the way that OLM package did. Neither Red Hat nor Isovalent supports this setup.

## Phase 1: mirror (connected side)
```bash
oc mirror -c imageset-cilium-1.20.5.yaml file://cilium-mirror --v2
./fetch-cilium-packages.sh            # -> ./cilium-packages/
# carry cilium-mirror/ + cilium-packages/ + this kit across
oc mirror -c imageset-cilium-1.20.5.yaml --from file://cilium-mirror docker://$REGISTRY --v2
```
Also mirror the full OCP 4.22.20 release payload as usual. `oc adm node-image create` (phase 3) needs nothing outside it.

## Phase 2: install on the 9 VMs (UPI)
1. `install-config.yaml`:
   - `networking.networkType: Cilium`
   - `clusterNetwork 10.128.0.0/14 hostPrefix 23`. This must match the values file.
   - `platform: none: {}`. This makes adding bare metal in phase 3 straightforward. With `platform: vsphere`, bare-metal workers are GA only from 4.22.13, and you must disable the vSphere CSI driver and clear the CCM `uninitialized` taint by hand.
2. Run `openshift-install create manifests --dir ./install`, then:
   `REGISTRY=... API_INT=api-int.<cluster>.<domain> ./render-cilium-manifests.sh ./install`
   Every image the script prints must start with `$REGISTRY`.
3. Run `openshift-install create ignition-configs` and boot as usual. Nodes go Ready only once the Cilium agents are up.
4. Checks: `cilium status -n cilium --wait`, then `oc get pods -n openshift-multus` and `oc get co network`. Also confirm no kube-proxy pods exist: `oc get ds -A | grep -i proxy` returns nothing.
5. LB test without BGP: see the header of `phase2-l2-lb-test.yaml`.

### Connectivity test (needs the test-image overrides; the default external targets are unreachable offline)
```bash
R=$REGISTRY
oc create ns cilium-test-1
oc label ns cilium-test-1 pod-security.kubernetes.io/enforce=privileged security.openshift.io/scc.podSecurityLabelSync=false --overwrite
oc adm policy add-scc-to-group privileged system:serviceaccounts:cilium-test-1
cilium connectivity test -n cilium \
  --curl-image $R/cilium/alpine-curl:v1.10.0 --json-mock-image $R/cilium/json-mock:v1.4.1 \
  --dns-test-server-image $R/coredns/coredns:v1.15.0 --test-conn-disrupt-image $R/cilium/test-connection-disruption:v0.0.18 \
  --frr-image $R/frrouting/frr:10.7.1 --socat-image $R/alpine/socat:1.8.1.3 \
  --echo-image $R/k8s-staging-gateway-api/echo-advanced:v20251204-v1.4.1 \
  --external-target <internal-fqdn> --external-other-target <internal-fqdn-2> \
  --external-ip <internal-ip> --external-other-ip <internal-ip-2> --external-cidr <internal-cidr>
```
Add `--print-image-artifacts` to see every image the CLI will use. Run `cilium connectivity perf` with `--performance-image $R/cilium/network-perf:3.22-1793546159-db4fb5f`.

## Phase 3: add bare metal and test BGP
1. Create the nodes config and ISO with `oc adm node-image create nodes-config.yaml`, boot the hosts, then run `oc adm node-image monitor --ip-addresses ...`. Approve the CSRs if there's no reverse DNS.
2. The Cilium DaemonSet lands on the new nodes by itself; no reinstall is needed. Label them `lab.cilium.io/lb=bgp`.
3. Apply `phase3-bgp-lb-test.yaml`. Its header lists the checks.

## Gotchas
- **Firewall between the VM and bare-metal segments:** UDP 8472 (VXLAN), TCP 4240 (health) plus ICMP, TCP 4244 (Hubble), and TCP 179 from the bare-metal nodes to the ToR.
- **MTU:** keep `MTU` in the values file at the lowest underlay MTU of both segments. If the VMs run at 1500 and the bare metal at 9000 and you let Cilium auto-detect, large pod packets between the two segments get dropped.
- **NSX segments:** if the VMs sit on NSX segments, the IP Discovery/SpoofGuard profile can drop ARP replies for the L2 VIPs. Raise the ARP binding limit or exempt the pool range.
- **L2 announcements:** one node answers ARP per VIP, so there's no load spreading before traffic enters the cluster, and `externalTrafficPolicy: Local` is not supported.
- **Day-2 lifecycle:** the day-0 manifests are applied once and not reconciled afterwards. Upgrade by rendering the same chart and values from ArgoCD (or `helm template | oc apply`).
