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

# reserved IP address
resource "google_compute_global_address" "default" {
  project = var.project_id

  provider = google-beta
  name     = format("l7-xlb-static-ip-%s", random_id.id.hex)
}

resource "google_compute_global_forwarding_rule" "gcr_echo_xlb_forwarding_80" {
  project = var.project_id

  name                  = format("l7-xlb-echo-forwarding-rule-http-%s", random_id.id.hex)
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.gcr_echo_http.id
  ip_address            = google_compute_global_address.default.id
}

resource "google_compute_target_http_proxy" "gcr_echo_http" {
  project = var.project_id

  name    = format("l7-xlb-echo-target-http-proxy-%s", random_id.id.hex)
  url_map = google_compute_url_map.gcr_echo_url_map.id
}

resource "google_compute_global_forwarding_rule" "gcr_echo_xlb_forwarding_443" {
  project = var.project_id

  name                  = format("l7-xlb-echo-forwarding-rule-https-%s", random_id.id.hex)
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.gcr_echo_https.id
  ip_address            = google_compute_global_address.default.id
}

resource "google_compute_target_https_proxy" "gcr_echo_https" {
  project = var.project_id

  name             = format("l7-xlb-echo-target-https-proxy-%s", random_id.id.hex)
  quic_override    = "DISABLE"
  url_map          = google_compute_url_map.gcr_echo_url_map.id
  ssl_certificates = [google_compute_ssl_certificate.default.id]
}



resource "google_compute_url_map" "gcr_echo_url_map" {
  project = var.project_id

  name            = format("l7-xlb-echo-url-map-%s", random_id.id.hex)
  default_service = google_compute_backend_service.gcr_echo_backend.id
}

