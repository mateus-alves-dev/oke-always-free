# AGENTS.md

This file provides guidance when working with code in this repository.

## Project

Terraform IaC that provisions an **OKE Basic** Kubernetes cluster on Oracle Cloud entirely within the **Always Free Tier**. The README is in Portuguese; user-facing docs/comments should match that language, but Terraform identifiers stay in English.

Terraform sources are split across files at the repo root: `versions.tf` (provider versions + commented S3 backend), `providers.tf`, `variables.tf`, `network.tf` (VCN/gateways/subnets/route tables/NSGs + rules), `cluster.tf` (image data source + cluster + node pool), `kubeconfig.tf`, `outputs.tf`, plus `terraform.tfvars.example`. There is no subdirectory — ignore the stale `cd oke-free-tf` text if it reappears anywhere.

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
```

`terraform.tfvars` is user-local (OCIDs, region) and must not be committed — only `terraform.tfvars.example` should be tracked.

## Git

Never commit or push unless the user explicitly asks for it in that message. `terraform.tfvars` and `kubeconfig` are gitignored and must stay out of version control.

## Architecture constraints (non-obvious, cost-critical)

These are load-bearing decisions that keep the stack inside Always Free. Do not change them without the user's explicit say-so:

- **Cluster `type` must be `"BASIC_CLUSTER"`.** Enhanced is ~US$73/month and is **not** Always Free.
- **Worker shape is `VM.Standard.A1.Flex` (ARM/aarch64), 2 nodes × 2 OCPU × 12 GB.** Total Always Free A1 budget is 4 OCPU + 24 GB — do not exceed. Container images therefore must be built for `linux/arm64`.
- **Boot volumes: 2 × 50 GB**, sized to fit under the 200 GB Always Free block storage cap shared with anything else in the tenancy.
- **Load balancer: 1 Flexible LB at 10 Mbps**, created on demand by a `Service type: LoadBalancer`. Don't provision a second one.
- **Image lookup**: an `oci_core_images.oke_arm` data source filters images by a regex on the K8s version. OKE ARM image names look like `Oracle-Linux-8.10-aarch64-2026.08.14-0-OKE-1.36.1-1699` — base-image date between `aarch64` and `OKE`, and no `v` prefix on the K8s version. The regex must account for both. When `kubernetes_version` changes, verify a matching image exists via `oci ce node-pool-options get --node-pool-option-id all` (`data.sources`).
- **A1.Flex capacity is region-dependent.** "Out of capacity" errors usually mean trying another region (us-ashburn-1, us-phoenix-1) before changing anything else.
- **Idle reclamation**: nodes with 95p CPU < 20% for 7 days get reaped. Any running pod prevents this — relevant when scoping demos or test workloads.

## Optional remote state

The README documents OCI Object Storage (S3-compatible, 20 GB Always Free) as a backend. The `backend "s3"` block lives in `versions.tf`, **commented out by default**; enabling it requires `<NAMESPACE>` substitution (`oci os ns get`) and `terraform init -migrate-state`. Do not enable the backend unprompted.
