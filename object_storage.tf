data "oci_objectstorage_namespace" "this" {
  compartment_id = var.tenancy_ocid
}

# Bucket privado para backups exportados pela aplicação ou por jobs do cluster.
# Sem versionamento para evitar consumo inesperado da cota de armazenamento.
resource "oci_objectstorage_bucket" "mysql_backups" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = "${var.cluster_name}-mysql-backups"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Disabled"

  depends_on = [terraform_data.always_free_guardrails]
}

# Limite conservador de 10 GB em toda a tenancy, na região home.
# Contas pagas/avaliação incluem 10 GB gratuitos na camada Standard;
# esta quota inclui também as demais camadas e compartimentos.
resource "oci_limits_quota" "object_storage_always_free" {
  compartment_id = var.tenancy_ocid
  name           = "${var.cluster_name}-object-storage-always-free"
  description    = "Limita Object Storage a 10 GB na tenancy para evitar uso pago."
  statements = [
    "Set object-storage quota storage-bytes to 10000000000 in tenancy"
  ]
}

# Grupo existente na tenancy; permissões IAM para jobs de backup são opcionais.
resource "oci_identity_dynamic_group" "mysql_backup_workers" {
  compartment_id = var.tenancy_ocid
  name           = "${var.cluster_name}-mysql-backup-workers"
  description    = "Instancias do compartimento autorizadas a executar o backup do MySQL."
  matching_rule  = "instance.compartment.id = '${var.compartment_ocid}'"
}
