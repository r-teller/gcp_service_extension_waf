resource "google_compute_health_check" "gce_se_waf_hc" {
  count   = alltrue([var.create_se_waf_backend_service]) ? 1 : 0

  project = var.project_id

  name = format("health-check-se-waf-8000-%s-%s", "glbl", local.random_suffix)
  http_health_check {
    port = 8000
  }
}

## Work around to handle IAP flag being set in backend when not compatible with Service-Extension
resource "local_file" "backend_service" {
  count   = alltrue([var.create_se_waf_backend_service]) ? 1 : 0

  content  = jsonencode(local.backend_service_spec)
  filename = format("%s/.staging/%s_backend_service.json", path.module, "glbl")

  depends_on = [
    google_compute_instance.gce_se_waf,
    google_compute_health_check.gce_se_waf_hc,
    google_compute_instance_group.gce_se_waf_ig,
  ]
}

resource "null_resource" "backend_service_create" {
  count   = alltrue([var.create_se_waf_backend_service]) ? 1 : 0
  
  triggers = {
    filename = local_file.backend_service[0].filename
    name     = local.backend_service_spec.name
  }

  lifecycle {
    replace_triggered_by = [local_file.backend_service]
  }

  provisioner "local-exec" {
    when    = create
    command = "gcloud compute backend-services import --global ${self.triggers.name} --source=${self.triggers.filename} --quiet"
  }


  depends_on = [
    google_compute_instance.gce_se_waf,
    google_compute_health_check.gce_se_waf_hc,
    google_compute_instance_group.gce_se_waf_ig,
  ]
}

resource "null_resource" "backend_service_destroy" {
  count   = alltrue([var.create_se_waf_backend_service]) ? 1 : 0

  triggers = {
    filename = local_file.backend_service[0].filename
    name     = local.backend_service_spec.name
  }

  provisioner "local-exec" {
    when    = destroy
    command = "gcloud compute backend-services delete --global ${self.triggers.name} --quiet"
  }

  depends_on = [
    google_compute_instance.gce_se_waf,
    google_compute_health_check.gce_se_waf_hc,
    google_compute_instance_group.gce_se_waf_ig,
    null_resource.backend_service_create
  ]
}
