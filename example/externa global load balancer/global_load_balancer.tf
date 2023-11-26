resource "google_compute_global_forwarding_rule" "default" {
  project = var.project_id

  name                  = "l7-xlb-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  #   ip_address            = google_compute_global_address.default.id
}

resource "google_compute_target_http_proxy" "default" {
  project = var.project_id

  name    = "l7-xlb-target-http-proxy"
  url_map = google_compute_url_map.default.id
}

resource "google_compute_url_map" "default" {
  project = var.project_id

  name            = "l7-xlb-url-map"
  default_service = google_compute_backend_service.default.id
}

# backend service with custom request and response headers
resource "google_compute_backend_service" "default" {
  project = var.project_id

  name = "l7-xlb-backend-service"

  load_balancing_scheme  = "EXTERNAL"
  protocol               = "HTTPS"
  enable_cdn             = false
  custom_request_headers = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  
  dynamic "backend" {
    for_each = google_compute_region_network_endpoint_group.cloudrun_neg
    content {
      group = backend.value.id
    }
  }
}

## https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_network_endpoint_group
resource "google_compute_region_network_endpoint_group" "cloudrun_neg" {
  for_each = google_cloud_run_service.default

  project = each.value.project

  name                  = format("cloudrun-neg-%s", module.gcp_utils.region_short_name_map[lower(each.key)])
  network_endpoint_type = "SERVERLESS"
  region                = each.key
  cloud_run {
    service = each.value.name
  }
}
