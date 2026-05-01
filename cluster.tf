data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "oke_arm" {
  compartment_id   = var.compartment_ocid
  operating_system = "Oracle Linux"
  shape            = "VM.Standard.A1.Flex"
  sort_by          = "TIMECREATED"
  sort_order       = "DESC"

  filter {
    name   = "display_name"
    values = ["^Oracle-Linux-[0-9.]+-aarch64-OKE-${replace(var.kubernetes_version, ".", "\\.")}-[0-9]+.*$"]
    regex  = true
  }
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
    image_id                = data.oci_core_images.oke_arm.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  node_config_details {
    size = var.node_count

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
}
