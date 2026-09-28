# Vault padrão e chave protegida por software permanecem elegíveis ao Always Free.
resource "oci_kms_vault" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.cluster_name}-vault"
  vault_type     = "DEFAULT"

  depends_on = [terraform_data.always_free_guardrails]
}

resource "oci_kms_key" "secrets" {
  compartment_id      = var.compartment_ocid
  display_name        = "${var.cluster_name}-secrets-key"
  management_endpoint = oci_kms_vault.this.management_endpoint
  protection_mode     = "SOFTWARE"

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

# A senha também permanece no estado do Terraform; proteja o backend/state local.
resource "oci_vault_secret" "mysql_admin" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.this.id
  key_id         = oci_kms_key.secrets.id
  secret_name    = "${var.cluster_name}-mysql-admin"

  secret_content {
    content_type = "BASE64"
    content      = base64encode(random_password.mysql_admin.result)
  }
}
