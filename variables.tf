variable "tenancy_ocid" {
  description = "OCID do tenancy (root). Console > Profile > Tenancy."
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment onde tudo será criado. Pode ser o tenancy_ocid pra usar a raiz."
  type        = string
}

variable "region" {
  description = "Região OCI. us-ashburn-1 e us-phoenix-1 costumam ter mais capacidade A1.Flex."
  type        = string
  default     = "us-ashburn-1"
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes. Confirmar disponibilidade: oci ce cluster-options get --cluster-option-id all"
  type        = string
  default     = "v1.36.1"
}

variable "cluster_name" {
  description = "Nome do cluster OKE."
  type        = string
  default     = "oke-free"
}

variable "ssh_public_key_path" {
  description = "Caminho para a chave SSH pública usada nos worker nodes."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "vcn_cidr" {
  description = "CIDR da VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR da subnet pública (API endpoint + LoadBalancer)."
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR da subnet privada (worker nodes)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "api_allowed_cidrs" {
  description = "CIDRs autorizados a falar com o Kubernetes API endpoint na porta 6443. Default permite tudo."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_count" {
  description = "Número de worker nodes. Always Free permite até 4 OCPU + 24 GB total em A1.Flex."
  type        = number
  default     = 2
}

variable "node_ocpus" {
  description = "OCPUs por node. 2 nodes × 2 OCPU = 4 OCPU (limite Always Free)."
  type        = number
  default     = 2
}

variable "node_memory_gb" {
  description = "Memória (GB) por node. 2 nodes × 12 GB = 24 GB (limite Always Free)."
  type        = number
  default     = 12
}

variable "boot_volume_size_gb" {
  description = "Tamanho do boot volume por node (GB). 2 × 50 = 100 GB, dentro dos 200 GB grátis."
  type        = number
  default     = 50
}
