module "gcp_utils" {
  source  = "terraform-google-modules/utils/google"
  version = "~> 0.3"
}

module "global_service_engine" {
  source = "../../module/External_Global"

  count = 1

  create_se_waf_backend_service   = true
  create_se_waf_traffic_extension = true

  global_se_waf_env = {
    se_debug                    = false,
    se_require_iap              = false,
    se_allowed_ipv4_cidr_ranges = ["0.0.0.0/0"]
    se_denied_ipv4_cidr_ranges  = ["174.138.50.160"]
  }



  project_id = var.project_id
  instance_configurations = [
    {
      region         = "us-central1",
      subnetwork     = google_compute_subnetwork.subnetwork_rfc1918["us-central1"].self_link
      zones          = ["us-central1-a"]
      instance_count = 1
    },
    # {
    #   region     = "us-east1",
    #   subnetwork = google_compute_subnetwork.subnetwork_rfc1918["us-east1"].self_link
    #   zones      = ["us-east1-b"]
    # }
  ]
  forwarding_rules = [
    google_compute_global_forwarding_rule.gcr_echo_xlb_forwarding_80.self_link,
    google_compute_global_forwarding_rule.gcr_echo_xlb_forwarding_443.self_link,
  ]
  random_suffix = random_id.id.hex

  depends_on = [
    google_compute_subnetwork.subnetwork_rfc1918
  ]
}
