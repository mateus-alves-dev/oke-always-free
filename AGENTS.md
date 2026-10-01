# AGENTS.md

This file provides guidance when working with code in this repository.

## Project

Terraform IaC that provisions an **OKE Basic** Kubernetes cluster on Oracle Cloud entirely within the **Always Free Tier**. The README is in Portuguese; user-facing docs/comments should match that language, but Terraform identifiers stay in English.

Terraform sources are split across files at the repo root: `versions.tf` (provider versions + commented S3 backend), `providers.tf`, `variables.tf`, `network.tf` (VCN/gateways/subnets/route tables/security list/NSGs + rules), `cluster.tf` (image data source + cluster + node pool), `mysql.tf` (MySQL HeatWave DB system + HeatWave node + its NSG and IAM policy), `bastion.tf`, `vault.tf`, `object_storage.tf`, `budget.tf`, `guardrails.tf` (Always Free preconditions), `kubeconfig.tf`, `outputs.tf`, plus `terraform.tfvars.example`. There is no subdirectory — ignore the stale `cd oke-free-tf` text if it reappears anywhere. Kubernetes manifests live in `k8s/`: `traefik-values.yaml` (the ingress controller, and the only place the Always Free LB annotations should exist) and `apps/` (Deployment + ClusterIP Service + Ingress examples, plus `mysql-client.yaml`, the Job that proves pod → MySQL access). Helper script: `scripts/check-load-balancers.sh`.

## Commands

```bash
terraform init
terraform plan
terraform apply
terraform destroy

# After apply, kubeconfig path is exposed as an output:
export KUBECONFIG=$(terraform output -raw kubeconfig_path)
kubectl get nodes

# List available K8s versions (use to update kubernetes_version):
oci ce cluster-options get --cluster-option-id all \
  --query 'data."kubernetes-versions"' --raw-output

# Prove MySQL is reachable from a pod (needs the mysql-app-credentials Secret; see README):
kubectl apply -f k8s/apps/mysql-client.yaml && kubectl logs job/mysql-check

# Confirm the single LoadBalancer is still Always Free (flexible, 10 Mbps):
./scripts/check-load-balancers.sh
```

`terraform.tfvars` is user-local (OCIDs, region) and must not be committed — only `terraform.tfvars.example` should be tracked.

## Git

Never commit or push unless the user explicitly asks for it in that message. `terraform.tfvars` and `kubeconfig` are gitignored and must stay out of version control.

## Architecture constraints (non-obvious, cost-critical)

These are load-bearing decisions that keep the stack inside Always Free. Do not change them without the user's explicit say-so:

- **Cluster `type` must be `"BASIC_CLUSTER"`.** Enhanced is ~US$73/month and is **not** Always Free.
- **Worker shape is `VM.Standard.A1.Flex` (ARM/aarch64), 2 nodes × 1 OCPU × 6 GB.** Current Oracle Always Free A1 budget is 1,500 OCPU-hours and 9,000 GB-hours per month, roughly 2 OCPU + 12 GB continuously — do not exceed. Container images therefore must be built for `linux/arm64`.
- **Boot volumes: 2 × 50 GB**, sized to fit under the 200 GB Always Free block storage cap shared with anything else in the tenancy.
- **Load balancer: exactly one Flexible LB at 10 Mbps**, created by the OCI CCM for Traefik's `Service type: LoadBalancer` (`k8s/traefik-values.yaml`). Apps are exposed as host-based `Ingress` resources behind it. Never create a second `Service type: LoadBalancer` — a second LB leaves Always Free.
- **Image lookup**: `oci_containerengine_node_pool_option.oke_arm` lists the OKE images and the local regex selects the K8s version. OKE ARM image names look like `Oracle-Linux-8.10-aarch64-2026.08.14-0-OKE-1.36.1-1699` — base-image date between `aarch64` and `OKE`, and no `v` prefix on the K8s version. When `kubernetes_version` changes, verify a matching image exists via `oci ce node-pool-options get --node-pool-option-id all` (`data.sources`).
- **A1.Flex capacity is region-dependent.** Always Free Compute and MySQL must be in the tenancy home region. For "out of capacity" errors, try another availability domain in that region or retry later; do not switch regions expecting the same Always Free eligibility. This tenancy's home region currently exposes a single AD (`FNGF:SA-SAOPAULO-1-AD-1`), so with one AD the only option is to retry later — the node pool's second `placement_config` falls back to the same AD and OKE keeps a single placement config.
- **MySQL HeatWave: exactly one `MySQL.Free` DB system (50 GiB) plus one single-node `HeatWave.Free` cluster**, in the home region, in the private subnet, one per tenancy. Never set `mysql_version` — the Always Free DB system always runs the latest version and is upgraded by maintenance. HA, read replicas, manual backups, PITR, and Database Management are paid or unavailable.
- **MySQL access is deliberately narrow**: TCP/3306 only from the workers NSG (pods) and from the Bastion's private endpoint IP/32. The bastion rule sources `private_endpoint_ip_address`, so recreating the bastion updates the rule. Port 33060 (X Protocol) stays closed.
- **Bastion is free** and creates no VM; only port-forwarding sessions are used, TTL ≤ 3 h. Its `name` must be alphanumeric (no hyphens), clients connect to `host.bastion.<region>.oci.oraclecloud.com` using the session OCID as the SSH user, and the client's public IP must be in `api_allowed_cidrs`.
- **Don't fight the OKE CCM.** With the default `securityListManagementMode: All`, the CCM adds ingress rules for the Traefik NodePorts (and 10256, kube-proxy) to the private subnet's security list; `ignore_changes = [ingress_security_rules]` on `oci_core_security_list.private` is intentional. Removing those rules breaks LB → backend traffic.
- **Vault stays on a `DEFAULT` vault with `SOFTWARE`-protected keys** (HSM key versions and virtual private vaults are paid). The MySQL admin password also lives in Terraform state, so protect the state file.
- **Object Storage: one private, non-versioned bucket**, with a tenancy-wide quota capping Object Storage at 10 GB — the statement must stay `in tenancy`.
- **Budget alerts are soft limits**: they e-mail `billing_alert_email` and never block spending.
- **Idle reclamation**: Oracle evaluates CPU, network, and A1 memory utilization over 7 days. A running pod alone does not prevent reclamation.

## Optional remote state

The README documents OCI Object Storage (S3-compatible, 20 GB Always Free) as a backend. The `backend "s3"` block lives in `versions.tf`, **commented out by default**; enabling it requires `<NAMESPACE>` substitution (`oci os ns get`) and `terraform init -migrate-state`. Do not enable the backend unprompted.
