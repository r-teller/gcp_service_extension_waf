## https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service
resource "google_cloud_run_service" "default" {
  for_each = toset(var.regions)

  project  = var.project_id
  name     = format("cloudrun-srv-%s", module.gcp_utils.region_short_name_map[lower(each.key)])
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


data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  for_each = google_cloud_run_service.default

  location = each.value.location
  project  = each.value.project
  service  = each.value.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

# resource "google_cloud_run_service" "default" {
#   name     = "cloudrun-srv"
#   location = "us-central1"

#   template {
#     spec {
#       containers {
#         image = "gcr.io/go-containerregistry/gcrane"
#       }
#     }
#   }

#   traffic {
#     percent         = 100
#     latest_revision = true
#   }
# }
