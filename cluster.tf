data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_containerengine_node_pool_option" "oke_arm" {
  node_pool_option_id = "all"
}

locals {
  # As imagens OKE aparecem nas opções do node pool, mas nem sempre em core_images.
  # Ex.: Oracle-Linux-9.8-aarch64-2026.08.14-0-OKE-1.36.1-1699
  oke_arm_images = {
    for source in data.oci_containerengine_node_pool_option.oke_arm.sources :
    source.source_name => source.image_id
    if length(regexall("^Oracle-Linux-[0-9.]+-aarch64-[0-9.]+-[0-9]+-OKE-${replace(trimprefix(var.kubernetes_version, "v"), ".", "\\.")}-[0-9]+$", source.source_name)) > 0
  }
  latest_oke_arm_image_name = try(reverse(sort(keys(local.oke_arm_images)))[0], "")
}

resource "oci_containerengine_cluster" "this" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = var.cluster_name
  vcn_id             = oci_core_vcn.this.id
  type               = "BASIC_CLUSTER"

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.public.id
    nsg_ids              = [oci_core_network_security_group.api.id]
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.public.id]

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }

  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }
}

resource "oci_containerengine_node_pool" "workers" {
  cluster_id         = oci_containerengine_cluster.this.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = "${var.cluster_name}-np"
  node_shape         = "VM.Standard.A1.Flex"

  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gb
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = lookup(local.oke_arm_images, local.latest_oke_arm_image_name, "")
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  node_config_details {
    size = var.node_count

    # Quando a tenancy expõe mais de um AD, os nodes são distribuídos entre eles.
    # Nesta tenancy só existe FNGF:SA-SAOPAULO-1-AD-1, então as duas entradas
    # apontam para o mesmo AD e o OKE mantém um único placement config; não há
    # outro AD para tentar quando falta capacidade A1 — apenas repetir depois.
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = oci_core_subnet.private.id
    }

    placement_configs {
      availability_domain = try(
        data.oci_identity_availability_domains.ads.availability_domains[1].name,
        data.oci_identity_availability_domains.ads.availability_domains[0].name
      )
      subnet_id = oci_core_subnet.private.id
    }

    nsg_ids = [oci_core_network_security_group.workers.id]
  }

  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  lifecycle {
    precondition {
      condition     = length(local.oke_arm_images) > 0
      error_message = "Nenhuma imagem OKE ARM corresponde à versão Kubernetes escolhida na região."
    }
  }
}
