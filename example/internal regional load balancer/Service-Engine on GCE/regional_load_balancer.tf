locals {
  forwarding_rule_domain = "demo.ihaz.cloud"
}

resource "tls_private_key" "default" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "default" {
  private_key_pem = tls_private_key.default.private_key_pem

  subject {
    common_name  = local.forwarding_rule_domain
    organization = "ACME Examples, Inc"
  }

  validity_period_hours = 8760
  dns_names             = [local.forwarding_rule_domain]
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "google_compute_ssl_certificate" "default" {
  project = var.project_id

  name        = format("default-cert-%s", random_id.id.hex)
  private_key = tls_private_key.default.private_key_pem
  certificate = tls_self_signed_cert.default.cert_pem
}

# forwarding rule
resource "google_compute_forwarding_rule" "gcr_echo_ilb_forwarding_80" {
  for_each = toset(var.regions)
  project  = var.project_id

  name                  = format("l7-ilb-echo-forwarding-rule-http-%s", random_id.id.hex)
  provider              = google-beta
  region                = each.key
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "80"
  network               = google_compute_network.vpc_network.id
  subnetwork            = google_compute_subnetwork.subnetwork_rfc1918[each.key].id
  target                = google_compute_region_target_http_proxy.gcr_echo_http[each.key].id
  network_tier          = "PREMIUM"

  allow_global_access = true
  depends_on          = [google_compute_subnetwork.subnetwork_gmp]
}

# HTTP target proxy
resource "google_compute_region_target_http_proxy" "gcr_echo_http" {
  for_each = toset(var.regions)
  project  = var.project_id

  name     = format("l7-ilb-target-http-proxy-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
  provider = google-beta
  region   = each.key
  url_map  = google_compute_region_url_map.gcr_echo_url_map[each.key].id
}

# URL map
resource "google_compute_region_url_map" "gcr_echo_url_map" {
  for_each = toset(var.regions)

  project = var.project_id
  region  = each.key

  name            = format("l7-xlb-echo-url-map-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
  default_service = google_compute_region_backend_service.gcr_echo_backend[each.key].id
  #   default_service = null
}

