data "oci_identity_tenancy" "this" {
  tenancy_id = var.tenancy_ocid
}

data "oci_identity_regions" "all" {}

locals {
  home_region = one([
    for region in data.oci_identity_regions.all.regions : region.name
    if region.key == data.oci_identity_tenancy.this.home_region_key
  ])
}

# Bloqueia configurações que ultrapassam a cota A1 e os volumes desta stack.
# A cota de Block Volume é compartilhada com outros recursos da tenancy.
resource "terraform_data" "always_free_guardrails" {
  input = {
    configured_region = var.region
    home_region       = local.home_region
  }

  lifecycle {
    precondition {
      condition     = var.region == local.home_region
      error_message = "Recursos Always Free devem ser criados na região home da tenancy."
    }

    precondition {
      condition     = var.node_count >= 1 && var.node_ocpus >= 1 && var.node_memory_gb >= 1 && var.node_count * var.node_ocpus <= 2 && var.node_count * var.node_memory_gb <= 12
      error_message = "A1 Always Free: até 2 OCPUs e 12 GB de memória no total."
    }

    precondition {
      condition     = var.boot_volume_size_gb >= 50 && var.node_count * var.boot_volume_size_gb <= 200
      error_message = "Os boot volumes desta stack devem caber na cota compartilhada de 200 GB."
    }

    precondition {
      condition     = length(var.api_allowed_cidrs) > 0 && !contains(var.api_allowed_cidrs, "0.0.0.0/0")
      error_message = "Informe CIDRs públicos específicos em api_allowed_cidrs para usar o Bastion."
    }
  }
}
