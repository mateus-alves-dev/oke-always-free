terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
  }

  # Remote state opcional via OCI Object Storage (S3-compat, Always Free até 20 GB).
  # Para ativar:
  #   1. oci os bucket create --name tf-states --versioning Enabled --compartment-id $COMPARTMENT_OCID
  #   2. Console > User Settings > Customer Secret Keys > Generate; salvar em ~/.aws/credentials
  #   3. oci os ns get  -> substituir <NAMESPACE> abaixo
  #   4. terraform init -migrate-state
  #
  # backend "s3" {
  #   bucket   = "tf-states"
  #   key      = "oke-free/terraform.tfstate"
  #   region   = "us-ashburn-1"
  #   endpoint = "https://<NAMESPACE>.compat.objectstorage.us-ashburn-1.oraclecloud.com"
  #
  #   skip_region_validation      = true
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   force_path_style            = true
  # }
}
