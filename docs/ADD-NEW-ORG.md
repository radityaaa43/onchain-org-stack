# Adding a New Org

Each org is a separate deployment of this repo onto its own k3s cluster.

---

## Prerequisites

- k3s cluster with `kubectl` access configured (current context points to the new cluster)
- `helm` 3.x installed
- `python3` with `pyyaml` (`pip3 install pyyaml`)
- `git` installed and SSH/HTTPS access to your fork

---

## Steps

### 1. Fork or clone this repo

Clone the repo to a machine that has `kubectl` access to the new cluster:

```bash
git clone https://github.com/YOUR_ORG/onchain-org-stack org2-stack
cd org2-stack
```

If using a single fork for multiple orgs, use a separate branch per org:

```bash
git checkout -b org2
```

### 2. Edit config.yaml

Open `config.yaml` and change the three required fields:

```yaml
org:
  name: org2                          # unique name, no spaces
  domain: org2.cluster.local          # domain for ingress hostnames
  email: admin@org2.example           # cert-manager ACME email

repo:
  url: https://github.com/YOUR_ORG/onchain-org-stack  # your fork URL
```

Optionally adjust `besu.chainId` (must match all orgs in a shared-chain-group),
`besu.baseNodePort` (must not conflict with other orgs on the same host), and
`paladin.baseNodePort`.

### 3. Render derived manifests

```bash
bash scripts/render.sh --write
```

This writes all templated manifests (ArgoCD Applications, Helm values, FireFly configs) using values from `config.yaml`.

### 4. Commit and push

```bash
git add -A && git commit -m "configure org2" && git push
```

ArgoCD will use this repo URL to pull manifests. The commit must be pushed before `bootstrap.sh` reaches the ArgoCD sync steps.

### 5. Run bootstrap

```bash
bash bootstrap.sh
```

This takes 10-15 minutes depending on cluster speed and image pull times. Watch the output for errors at each step.

### 6. Verify

```bash
kubectl get applications -n argocd
```

All applications should be `Synced` and `Healthy`. If any are `OutOfSync` or `Degraded`, check:

```bash
kubectl describe application <name> -n argocd
kubectl get pods -n paladin
kubectl get pods -n firefly
```

### 7. Access

| Service     | URL                                  |
|-------------|--------------------------------------|
| FireFly API | `https://firefly.<domain>/api/v1`    |
| FireFly UI  | `https://firefly.<domain>/ui`        |
| Paladin UI  | `https://paladin1.<domain>`          |
| ArgoCD      | `https://argocd.<domain>`            |

Replace `<domain>` with the value you set in `config.yaml → org.domain`.
