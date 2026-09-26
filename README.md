# OKE on Oracle Always Free with Terraform

Provisions a managed Kubernetes cluster (OKE Basic) on Oracle Cloud using
**100% Always Free Tier resources**:

- OKE Basic control plane: **free**
- 2 ARM worker nodes (VM.Standard.A1.Flex) with 2 OCPU + 12 GB each = **4 OCPU + 24 GB total**
- VCN, subnets, NSGs, IGW, NAT GW, Service GW: free
- Block storage (boot volumes 2 × 50 GB): within the 200 GB free allowance
- 1 Flexible Load Balancer at 10 Mbps: free (created on demand via a Service of type LoadBalancer)

## Prerequisites

1. Oracle Cloud account (cloud.oracle.com)
2. Terraform >= 1.5 installed
3. OCI CLI installed and configured:
   ```bash
   brew install oci-cli   # or another method
   oci setup config        # generates ~/.oci/config and the key pair
   ```
4. `kubectl` installed

## Setup

```bash
# 1. Configure your variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your OCIDs

# 2. Provision
terraform init
terraform plan
terraform apply

# 3. Export the kubeconfig
export KUBECONFIG=$(terraform output -raw kubeconfig_path)
kubectl get nodes
```

## Finding your OCIDs

- **Tenancy OCID**: Console > Profile (top-right corner) > Tenancy: <name> > copy OCID
- **Compartment OCID**: Identity & Security > Compartments > pick yours (or use the tenancy OCID for the root)

## Available Kubernetes versions

```bash
oci ce cluster-options get --cluster-option-id all \
  --query 'data."kubernetes-versions"' --raw-output
```

Update `kubernetes_version` in `terraform.tfvars` to the latest stable release.

## Remote state (optional, recommended)

OCI Object Storage is S3-compatible and is part of Always Free (up to 20 GB):

```bash
# Create the bucket
oci os bucket create --name tf-states --versioning Enabled \
  --compartment-id $COMPARTMENT_OCID

# In the console: User Settings > Customer Secret Keys > Generate
# Save it under ~/.aws/credentials as [default]
```

Uncomment the `backend "s3"` block in `versions.tf`, replace `<NAMESPACE>` with
your Object Storage namespace (`oci os ns get`), and run `terraform init -migrate-state`.

## Gotchas

- **"Out of capacity" on the A1.Flex shape**: try another region (us-ashburn-1 and
  us-phoenix-1 usually have more capacity than sa-saopaulo-1). If it persists,
  consider upgrading to Pay As You Go — the Always Free limits remain free,
  but the "guardrails" disappear (be careful not to overrun them).
- **Idle reclamation**: VMs with 95p CPU < 20% for 7 days are removed. Keep
  some workload active (any pod is enough).
- **Enhanced vs Basic**: make sure `type = "BASIC_CLUSTER"` on the cluster resource.
  Enhanced costs ~US$ 73/month.
- **K8s version**: the regex in `oci_core_images.oke_arm` matches OKE ARM image names
  such as `Oracle-Linux-8.10-aarch64-2026.08.14-0-OKE-1.36.1-1699` — note the base-image
  date between `aarch64` and `OKE`, and that the image name has no `v` prefix. If you
  change `kubernetes_version`, confirm a matching image exists:
  ```bash
  oci ce node-pool-options get --node-pool-option-id all \
    --query 'data.sources[?contains("source-name", `aarch64-OKE`)].{name:"source-name", id:"image-id"}'
  ```

## Cleanup

```bash
terraform destroy
```

## Next steps

- Install `cert-manager` for automatic TLS (Let's Encrypt)
- Install `external-dns` to create DNS records automatically
- Configure `ingress-nginx` or use the native LB through a Service `type: LoadBalancer`
- Build ARM64 images: `docker buildx build --platform linux/arm64 ...`
- Push to OCIR (Oracle Container Registry, 10 GB free)
