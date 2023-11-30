module "gcp_utils" {
  source  = "terraform-google-modules/utils/google"
  version = "~> 0.3"
}

data "google_compute_zones" "zones" {
  for_each = toset(var.regions)

  project = var.project_id
  region  = each.key
}
