# OKE no Oracle Always Free com Terraform

Provisiona um cluster Kubernetes gerenciado (OKE Basic) na Oracle Cloud usando
**100% recursos do Always Free Tier**:

- Control plane OKE Basic: **grátis**
- 2 worker nodes ARM (VM.Standard.A1.Flex) com 2 OCPU + 12 GB cada = **4 OCPU + 24 GB total**
- VCN, subnets, NSGs, IGW, NAT GW, Service GW: grátis
- Block storage (boot volumes 2 × 50 GB): dentro dos 200 GB grátis
- 1 Flexible Load Balancer 10 Mbps: grátis (criado sob demanda via Service do tipo LoadBalancer)

## Pré-requisitos

1. Conta na Oracle Cloud (cloud.oracle.com)
2. Terraform >= 1.5 instalado
3. OCI CLI instalado e configurado:
   ```bash
   brew install oci-cli   # ou outro método
   oci setup config        # gera ~/.oci/config e o par de chaves
   ```
4. `kubectl` instalado

## Setup

```bash
# 1. Configure suas variáveis
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars com seus OCIDs

# 2. Provisione
terraform init
terraform plan
terraform apply

# 3. Exporte o kubeconfig
export KUBECONFIG=$(terraform output -raw kubeconfig_path)
kubectl get nodes
```

## Encontrar seus OCIDs

- **Tenancy OCID**: Console > Profile (canto superior direito) > Tenancy: <nome> > copiar OCID
- **Compartment OCID**: Identity & Security > Compartments > escolha o seu (ou use o tenancy OCID para a raiz)

## Versões do Kubernetes disponíveis

```bash
oci ce cluster-options get --cluster-option-id all \
  --query 'data."kubernetes-versions"' --raw-output
```

Atualize `kubernetes_version` no `terraform.tfvars` para a mais recente estável.

## State remoto (opcional, recomendado)

O Object Storage da OCI é S3-compatível e está no Always Free (até 20 GB):

```bash
# Cria o bucket
oci os bucket create --name tf-states --versioning Enabled \
  --compartment-id $COMPARTMENT_OCID

# No console: User Settings > Customer Secret Keys > Generate
# Salve em ~/.aws/credentials como [default]
```

Descomente o bloco `backend "s3"` em `versions.tf`, substitua `<NAMESPACE>` pelo
seu Object Storage namespace (`oci os ns get`), e rode `terraform init -migrate-state`.

## Pegadinhas

- **"Out of capacity" no shape A1.Flex**: tente outra região (us-ashburn-1 e
  us-phoenix-1 costumam ter mais capacidade que sa-saopaulo-1). Se persistir,
  considere upgrade pra Pay As You Go — os limites Always Free continuam grátis,
  mas os "guardrails" somem (cuidado pra não estourar).
- **Idle reclamation**: VMs com CPU 95p < 20% por 7 dias são removidas. Mantenha
  algum workload ativo (qualquer pod já resolve).
- **Enhanced vs Basic**: garante que `type = "BASIC_CLUSTER"` no recurso do cluster.
  Enhanced custa ~US$ 73/mês.
- **Versão do K8s**: a regex em `oci_core_images.oke_arm` busca imagens com nome
  matching a versão. Se mudar a versão, confirme que existe imagem aarch64-OKE
  pra ela com `oci compute image list ...`.

## Limpeza

```bash
terraform destroy
```

## Próximos passos

- Instalar `cert-manager` pra TLS automático (Let's Encrypt)
- Instalar `external-dns` pra criar registros DNS automaticamente
- Configurar `ingress-nginx` ou usar o LB nativo via Service `type: LoadBalancer`
- Build de imagens ARM64: `docker buildx build --platform linux/arm64 ...`
- Push pro OCIR (Oracle Container Registry, 10 GB grátis)