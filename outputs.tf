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
