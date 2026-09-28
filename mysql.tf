resource "oci_core_network_security_group" "mysql" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-nsg-mysql"
}

# Apenas os workers do cluster podem abrir conexões MySQL diretas.
resource "oci_core_network_security_group_security_rule" "mysql_from_workers" {
  network_security_group_id = oci_core_network_security_group.mysql.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = oci_core_network_security_group.workers.id

  tcp_options {
    destination_port_range {
      min = 3306
      max = 3306
    }
  }
}

# O Bastion usa seu IP privado de origem para o túnel de port forwarding.
resource "oci_core_network_security_group_security_rule" "mysql_from_bastion" {
  network_security_group_id = oci_core_network_security_group.mysql.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source_type               = "CIDR_BLOCK"
  source                    = "${oci_bastion_bastion.mysql.private_endpoint_ip_address}/32"

  tcp_options {
    destination_port_range {
      min = 3306
      max = 3306
    }
  }
}

# O serviço MySQL precisa de permissões para associar seu VNIC ao NSG.
# Restringe o principal de recurso aos DB systems deste compartimento.
resource "oci_identity_policy" "mysql_nsg" {
  compartment_id = var.tenancy_ocid
  name           = "${var.cluster_name}-mysql-nsg"
  description    = "Permite ao MySQL HeatWave associar seu VNIC ao NSG no compartimento."
  statements = [
    "Allow any-user to {NETWORK_SECURITY_GROUP_UPDATE_MEMBERS} in compartment id ${var.compartment_ocid} where all {request.principal.type='mysqldbsystem', request.resource.compartment.id='${var.compartment_ocid}'}",
    "Allow any-user to {VNIC_CREATE, VNIC_UPDATE, VNIC_ASSOCIATE_NETWORK_SECURITY_GROUP, VNIC_DISASSOCIATE_NETWORK_SECURITY_GROUP} in compartment id ${var.compartment_ocid} where all {request.principal.type='mysqldbsystem', request.resource.compartment.id='${var.compartment_ocid}'}"
  ]
}

resource "random_password" "mysql_admin" {
  length           = 16
  special          = true
  override_special = "_#-"
}

resource "oci_mysql_mysql_db_system" "this" {
  compartment_id          = var.compartment_ocid
  availability_domain     = data.oci_identity_availability_domains.ads.availability_domains[0].name
  subnet_id               = oci_core_subnet.private.id
  nsg_ids                 = [oci_core_network_security_group.mysql.id]
  display_name            = "${var.cluster_name}-mysql"
  shape_name              = "MySQL.Free"
  data_storage_size_in_gb = 50
  admin_username          = var.mysql_admin_username
  admin_password          = random_password.mysql_admin.result
  port                    = 3306

  depends_on = [terraform_data.always_free_guardrails, oci_identity_policy.mysql_nsg]
}

resource "oci_mysql_heat_wave_cluster" "this" {
  db_system_id = oci_mysql_mysql_db_system.this.id
  shape_name   = "HeatWave.Free"
  cluster_size = 1
}
