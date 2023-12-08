## https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service
resource "google_cloud_run_service" "gcr_echo" {
  for_each = toset(var.regions)

  project  = var.project_id
  name     = format("gcr-echo-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
  location = each.key

  template {
    spec {
      containers {
        image = "rteller/echo:latest"
        ports {
          container_port = 80
        }
      }
    }
  }
  metadata {
    annotations = {
      "run.googleapis.com/ingress" = "internal-and-cloud-load-balancing"
    }
  }
  traffic {
    percent         = 100
    latest_revision = true
  }
}

## https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_network_endpoint_group
resource "google_compute_region_network_endpoint_group" "gcr_echo_neg" {
  for_each = google_cloud_run_service.gcr_echo

  project = each.value.project

  name                  = format("gcr-echo-neg-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
  network_endpoint_type = "SERVERLESS"
  region                = each.key
  cloud_run {
    service = each.value.name
  }
}

data "google_iam_policy" "gcr_echo_noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "gcr_echo_noauth" {
  for_each = google_cloud_run_service.gcr_echo

  location = each.value.location
  project  = each.value.project
  service  = each.value.name

  policy_data = data.google_iam_policy.gcr_echo_noauth.policy_data
}

# backend service with custom request and response headers
resource "google_compute_backend_service" "gcr_echo_backend" {
  project = var.project_id

  name = format("l7-xlb-echo-bs-%s", random_id.id.hex)

  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"
  enable_cdn            = false

  dynamic "backend" {
    for_each = google_compute_region_network_endpoint_group.gcr_echo_neg
    content {
      group = backend.value.id
    }
  }
}

