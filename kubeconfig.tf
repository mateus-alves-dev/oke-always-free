data "oci_containerengine_cluster_kube_config" "this" {
  cluster_id = oci_containerengine_cluster.this.id
  endpoint   = "PUBLIC_ENDPOINT"
}

resource "local_file" "kubeconfig" {
  content         = data.oci_containerengine_cluster_kube_config.this.content
  filename        = "${path.module}/kubeconfig"
  file_permission = "0600"
}

# O acesso privado via WARP mantém o kubeconfig público disponível para recuperação.
data "oci_containerengine_cluster_kube_config" "private" {
  cluster_id = oci_containerengine_cluster.this.id
  endpoint   = "PRIVATE_ENDPOINT"
}

resource "local_file" "kubeconfig_private" {
  content         = data.oci_containerengine_cluster_kube_config.private.content
  filename        = "${path.module}/kubeconfig-private"
  file_permission = "0600"
}
