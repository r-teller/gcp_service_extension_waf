resource "random_id" "id" {
  byte_length = 2
}

resource "random_integer" "region_number" {
  for_each = toset(var.regions)
  min      = 0
  max      = 254

  seed = each.key
}

resource "google_compute_network" "vpc_network" {
  project = var.project_id

  name                    = format("vpc-service-extension-demo-l7-ilb-%s", random_id.id.hex)
  auto_create_subnetworks = false
  mtu                     = 1460
}

resource "google_compute_firewall" "firewall_rule_iap" {
  description = "This rule will allow IAP ranges access to all VMs on all ports."

  direction = "INGRESS"
  disabled  = false
  name      = format("fw-r-allow-iap-%s", random_id.id.hex)
  network   = google_compute_network.vpc_network.name
  priority  = 65530
  project   = var.project_id
  source_ranges = [
    "35.235.240.0/20",
  ]

  allow {
    ports    = []
    protocol = "tcp"
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "firewall_rule_gfe" {
  description = "This rule will allow GFE ranges access to all VMs and Ports, GFE is used for Cloud Load Balancing."
  direction   = "INGRESS"
  disabled    = false
  name        = format("fw-r-allow-gfe-%s", random_id.id.hex)
  network     = google_compute_network.vpc_network.name
  priority    = 65530
  project     = var.project_id
  source_ranges = [
    "130.211.0.0/22",
    "209.85.152.0/22",
    "209.85.204.0/22",
    "35.191.0.0/16",
  ]

  allow {
    ports    = []
    protocol = "tcp"
  }
  allow {
    ports    = []
    protocol = "udp"
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "firewall_rule_se_waf" {
  description = "This rule will allow internal ranges access to all VMS on port 8080 and 8443."
  direction   = "INGRESS"
  disabled    = false
  name        = format("fw-r-allow-se-waf-%s", random_id.id.hex)
  network     = google_compute_network.vpc_network.name
  priority    = 65530
  project     = var.project_id
  source_ranges = [
    "10.0.0.0/8",
  ]

  allow {
    ports    = [8080, 8443]
    protocol = "tcp"
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}


resource "google_compute_subnetwork" "subnetwork_rfc1918" {
  project = var.project_id

  for_each      = toset(var.regions)
  name          = format("subnet-rfc1918-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
  ip_cidr_range = format("10.%d.0.0/24", random_integer.region_number[each.key].id)
  region        = lower(each.key)
  network       = google_compute_network.vpc_network.id

  purpose = "PRIVATE"
}

resource "google_compute_subnetwork" "subnetwork_psc" {
  project = var.project_id

  for_each      = toset(var.regions)
  name          = format("subnet-psc-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
  ip_cidr_range = format("10.%d.1.0/24", random_integer.region_number[each.key].id)
  region        = lower(each.key)
  network       = google_compute_network.vpc_network.id

  purpose = "PRIVATE_SERVICE_CONNECT"
}

resource "google_compute_subnetwork" "subnetwork_rmp" {
  project = var.project_id

  for_each      = toset(var.regions)
  name          = format("subnet-rmp-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
  ip_cidr_range = format("10.%d.2.0/24", random_integer.region_number[each.key].id)
  region        = lower(each.key)
  network       = google_compute_network.vpc_network.id
  role          = "ACTIVE"
  purpose       = "REGIONAL_MANAGED_PROXY"
}



resource "google_compute_subnetwork" "subnetwork_gmp" {
  project = var.project_id

  for_each      = toset(var.regions)
  name          = format("subnet-gmp-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
  ip_cidr_range = format("10.%d.3.0/24", random_integer.region_number[each.key].id)
  region        = lower(each.key)
  network       = google_compute_network.vpc_network.id
  role          = "ACTIVE"

  purpose = "GLOBAL_MANAGED_PROXY"
}

resource "google_compute_router" "router" {
  project = var.project_id

  for_each = toset(var.regions)

  name    = format("cr-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
  region  = each.key
  network = google_compute_network.vpc_network.id
}

resource "google_compute_router_nat" "nat" {
  project = var.project_id

  for_each = google_compute_router.router

  name                               = format("nat-gw-%s-%s", module.gcp_utils.region_short_name_map[lower(each.value.region)], random_id.id.hex)
  router                             = each.value.name
  region                             = each.value.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
