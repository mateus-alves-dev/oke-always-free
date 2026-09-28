variable "tenancy_ocid" {
  description = "OCID do tenancy (root). Console > Profile > Tenancy."
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment onde tudo será criado. Pode ser o tenancy_ocid pra usar a raiz."
  type        = string
}

variable "region" {
  description = "Região home da tenancy OCI; recursos Always Free da stack dependem dela."
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
  description = "CIDRs públicos autorizados a acessar a API Kubernetes e as sessões do Bastion. Configure seu IP público /32."
  type        = list(string)
  default     = []
}

variable "node_count" {
  description = "Número de worker nodes. A cota A1 Always Free é de 2 OCPU e 12 GB no total."
  type        = number
  default     = 2
}

variable "node_ocpus" {
  description = "OCPUs por node. 2 nodes × 1 OCPU = 2 OCPU no total."
  type        = number
  default     = 1
}

variable "node_memory_gb" {
  description = "Memória (GB) por node. 2 nodes × 6 GB = 12 GB no total."
  type        = number
  default     = 6
}

variable "boot_volume_size_gb" {
  description = "Tamanho do boot volume por node (GB). 2 × 50 = 100 GB, dentro dos 200 GB grátis."
  type        = number
  default     = 50
}

variable "mysql_admin_username" {
  description = "Usuário administrador do MySQL HeatWave."
  type        = string
  default     = "admin"
}

variable "billing_alert_email" {
  description = "E-mail que receberá os alertas de gasto mensal da tenancy."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.billing_alert_email))
    error_message = "Informe um endereço de e-mail válido em billing_alert_email."
  }
}
