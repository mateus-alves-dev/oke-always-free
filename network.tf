data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.cluster_name}-vcn"
  dns_label      = "okefree"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-igw"
  enabled        = true
}

resource "oci_core_nat_gateway" "nat" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-nat"
}

resource "oci_core_service_gateway" "sgw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-sgw"

  services {
    service_id = data.oci_core_services.all_services.services[0].id
  }
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-rt-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-rt-private"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat.id
  }

  route_rules {
    destination       = data.oci_core_services.all_services.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
  }
}

# A subnet privada não herda a lista padrão da VCN (que permite SSH público).
# As entradas necessárias aos workers e ao MySQL ficam nos respectivos NSGs.
resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-sl-private"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = var.public_subnet_cidr
  display_name               = "${var.cluster_name}-public"
  dns_label                  = "public"
  route_table_id             = oci_core_route_table.public.id
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = var.private_subnet_cidr
  display_name               = "${var.cluster_name}-private"
  dns_label                  = "private"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_network_security_group" "api" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-nsg-api"
}

resource "oci_core_network_security_group" "workers" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-nsg-workers"
}

# ----- Regras: workers -----

resource "oci_core_network_security_group_security_rule" "workers_egress_internet" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination_type          = "CIDR_BLOCK"
  destination               = "0.0.0.0/0"
}

resource "oci_core_network_security_group_security_rule" "workers_egress_oci_services" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination_type          = "SERVICE_CIDR_BLOCK"
  destination               = data.oci_core_services.all_services.services[0].cidr_block
}

resource "oci_core_network_security_group_security_rule" "workers_ingress_self" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = oci_core_network_security_group.workers.id
}

resource "oci_core_network_security_group_security_rule" "workers_ingress_kubelet_from_api" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = oci_core_network_security_group.api.id

  tcp_options {
    destination_port_range {
      min = 10250
      max = 10250
    }
  }
}

resource "oci_core_network_security_group_security_rule" "workers_ingress_pmtu_from_api" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "1" # ICMP
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = oci_core_network_security_group.api.id

  icmp_options {
    type = 3
    code = 4
  }
}

resource "oci_core_network_security_group_security_rule" "workers_ingress_pmtu_from_internet" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "1" # ICMP
  source_type               = "CIDR_BLOCK"
  source                    = "0.0.0.0/0"

  icmp_options {
    type = 3
    code = 4
  }
}

resource "oci_core_network_security_group_security_rule" "workers_ingress_nodeport" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source_type               = "CIDR_BLOCK"
  source                    = "0.0.0.0/0"

  tcp_options {
    destination_port_range {
      min = 30000
      max = 32767
    }
  }
}

# ----- Regras: api endpoint -----

resource "oci_core_network_security_group_security_rule" "api_egress_workers_6443" {
  network_security_group_id = oci_core_network_security_group.api.id
  direction                 = "EGRESS"
  protocol                  = "6" # TCP
  destination_type          = "NETWORK_SECURITY_GROUP"
  destination               = oci_core_network_security_group.workers.id

  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "api_egress_workers_kubelet" {
  network_security_group_id = oci_core_network_security_group.api.id
  direction                 = "EGRESS"
  protocol                  = "6" # TCP
  destination_type          = "NETWORK_SECURITY_GROUP"
  destination               = oci_core_network_security_group.workers.id

  tcp_options {
    destination_port_range {
      min = 10250
      max = 10250
    }
  }
}

resource "oci_core_network_security_group_security_rule" "api_egress_workers_pmtu" {
  network_security_group_id = oci_core_network_security_group.api.id
  direction                 = "EGRESS"
  protocol                  = "1" # ICMP
  destination_type          = "NETWORK_SECURITY_GROUP"
  destination               = oci_core_network_security_group.workers.id

  icmp_options {
    type = 3
    code = 4
  }
}

resource "oci_core_network_security_group_security_rule" "api_egress_oci_services" {
  network_security_group_id = oci_core_network_security_group.api.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination_type          = "SERVICE_CIDR_BLOCK"
  destination               = data.oci_core_services.all_services.services[0].cidr_block
}

resource "oci_core_network_security_group_security_rule" "api_ingress_kubectl" {
  for_each = toset(var.api_allowed_cidrs)

  network_security_group_id = oci_core_network_security_group.api.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source_type               = "CIDR_BLOCK"
  source                    = each.value

  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "api_ingress_workers_6443" {
  network_security_group_id = oci_core_network_security_group.api.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = oci_core_network_security_group.workers.id

  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "api_ingress_workers_12250" {
  network_security_group_id = oci_core_network_security_group.api.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = oci_core_network_security_group.workers.id

  tcp_options {
    destination_port_range {
      min = 12250
      max = 12250
    }
  }
}

resource "oci_core_network_security_group_security_rule" "api_ingress_workers_pmtu" {
  network_security_group_id = oci_core_network_security_group.api.id
  direction                 = "INGRESS"
  protocol                  = "1" # ICMP
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = oci_core_network_security_group.workers.id

  icmp_options {
    type = 3
    code = 4
  }
}
