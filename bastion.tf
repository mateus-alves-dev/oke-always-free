# O Bastion não cria uma VM. Sessões de port forwarding dão acesso temporário
# ao endpoint privado do MySQL na porta 3306. É um serviço gratuito e não
# consome nenhuma cota Always Free. O nome deve ser alfanumérico.
resource "oci_bastion_bastion" "mysql" {
  compartment_id               = var.compartment_ocid
  name                         = "${replace(var.cluster_name, "-", "")}bastion"
  bastion_type                 = "STANDARD"
  target_subnet_id             = oci_core_subnet.private.id
  client_cidr_block_allow_list = var.api_allowed_cidrs
  max_session_ttl_in_seconds   = 10800

  depends_on = [terraform_data.always_free_guardrails]
}
