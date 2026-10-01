output "kubeconfig_path" {
  description = "Caminho do arquivo kubeconfig gerado. Use: export KUBECONFIG=$(terraform output -raw kubeconfig_path)"
  value       = local_file.kubeconfig.filename
}

output "cluster_id" {
  description = "OCID do cluster OKE."
  value       = oci_containerengine_cluster.this.id
}

output "cluster_endpoint" {
  description = "Endpoint público do Kubernetes API."
  value       = oci_containerengine_cluster.this.endpoints[0].public_endpoint
}

output "node_pool_id" {
  description = "OCID do node pool."
  value       = oci_containerengine_node_pool.workers.id
}

output "lb_subnet_id" {
  description = "OCID da subnet pública usada pelo LoadBalancer (Service type=LoadBalancer)."
  value       = oci_core_subnet.public.id
}

output "vcn_id" {
  description = "OCID da VCN."
  value       = oci_core_vcn.this.id
}

output "mysql_ip" {
  description = "IP privado do MySQL para aplicações no cluster e sessões do Bastion."
  value       = oci_mysql_mysql_db_system.this.ip_address
}

output "mysql_admin_username" {
  description = "Usuário administrador do MySQL (usado por aplicações e pelo túnel do Bastion)."
  value       = var.mysql_admin_username
}

output "mysql_heatwave_state" {
  description = "Estado do nó HeatWave Always Free."
  value       = oci_mysql_heat_wave_cluster.this.state
}

output "bastion_id" {
  description = "OCID do Bastion usado para criar sessões de port forwarding."
  value       = oci_bastion_bastion.mysql.id
}

output "mysql_backup_bucket_name" {
  description = "Nome do bucket privado de backups."
  value       = oci_objectstorage_bucket.mysql_backups.name
}

output "vault_id" {
  description = "OCID do Vault padrão."
  value       = oci_kms_vault.this.id
}

output "mysql_admin_secret_id" {
  description = "OCID do segredo com a senha do administrador MySQL."
  value       = oci_vault_secret.mysql_admin.id
}
