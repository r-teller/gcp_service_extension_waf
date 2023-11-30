resource "random_integer" "region_number" {
  for_each = toset(var.regions)
  min      = 0
  max      = 255

  seed = each.key
}

resource "google_compute_network" "vpc_network" {
  project = var.project_id

  name                    = "vpc-service-extension-demo-l7-xlb"
  auto_create_subnetworks = false
  mtu                     = 1460
}

resource "google_compute_subnetwork" "subnetwork_rfc1918" {
  project = var.project_id

  for_each      = toset(var.regions)
  name          = format("subnet-rfc1918-%s", module.gcp_utils.region_short_name_map[lower(each.key)])
  ip_cidr_range = format("10.%d.0.0/24", random_integer.region_number[each.key].id)
  region        = lower(each.key)
  network       = google_compute_network.vpc_network.id

  purpose = "PRIVATE"
}

resource "google_compute_subnetwork" "subnetwork_psc" {
  project = var.project_id

  for_each      = toset(var.regions)
  name          = format("subnet-psc-%s", module.gcp_utils.region_short_name_map[lower(each.key)])
  ip_cidr_range = format("10.%d.1.0/24", random_integer.region_number[each.key].id)
  region        = lower(each.key)
  network       = google_compute_network.vpc_network.id

  purpose = "PRIVATE_SERVICE_CONNECT"
}

resource "google_compute_router" "router" {
  project = var.project_id

  for_each = toset(var.regions)

  name    = format("cr-%s", module.gcp_utils.region_short_name_map[lower(each.key)])
  region  = each.key
  network = google_compute_network.vpc_network.id
}

resource "google_compute_router_nat" "nat" {
  project = var.project_id

  for_each = google_compute_router.router

  name                               = format("nat-gw-%s", module.gcp_utils.region_short_name_map[lower(each.value.region)])
  router                             = each.value.name
  region                             = each.value.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

locals {
  firewall_rule_path = "./rules"
  firewall_rule_sets = fileset(local.firewall_rule_path, "*.json")
  firewall_rules = flatten([for rules in local.firewall_rule_sets : [
    for rule in jsondecode(file("${local.firewall_rule_path}/${rules}")) :
    merge(rule, { fileName = split(".", rules)[0] })
    ]
  ])
}


module "firewall_rules" {
  source = "r-teller/firewall-rules/google"

  project_id = var.project_id
  network    = google_compute_network.vpc_network.name

  firewall_rules = local.firewall_rules
}
