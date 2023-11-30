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

  name        = "default-cert"
  private_key = tls_private_key.default.private_key_pem
  certificate = tls_self_signed_cert.default.cert_pem
}

# reserved IP address
resource "google_compute_global_address" "default" {
  project = var.project_id

  provider = google-beta
  name     = "l7-xlb-static-ip"
}

resource "google_compute_global_forwarding_rule" "cloudrun_srv_echo_forwarding_80" {
  project = var.project_id

  name                  = "l7-xlb-echo-forwarding-rule-http"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.cloudrun_srv_echo_http.id
  ip_address            = google_compute_global_address.default.id
}

resource "google_compute_target_http_proxy" "cloudrun_srv_echo_http" {
  project = var.project_id

  name    = "l7-xlb-echo-target-http-proxy"
  url_map = google_compute_url_map.cloudrun_srv_echo_url_map.id
}

resource "google_compute_global_forwarding_rule" "cloudrun_srv_echo_forwarding_443" {
  project = var.project_id

  name                  = "l7-xlb-echo-forwarding-rule-https"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.cloudrun_srv_echo_https.id
  ip_address            = google_compute_global_address.default.id
}

resource "google_compute_target_https_proxy" "cloudrun_srv_echo_https" {
  project = var.project_id

  name             = "l7-xlb-echo-target-https-proxy"
  quic_override    = "DISABLE"
  url_map          = google_compute_url_map.cloudrun_srv_echo_url_map.id
  ssl_certificates = [google_compute_ssl_certificate.default.id]
}



resource "google_compute_url_map" "cloudrun_srv_echo_url_map" {
  project = var.project_id

  name            = "l7-xlb-echo-url-map"
  default_service = google_compute_backend_service.cloudrun_srv_echo_backend.id
}
