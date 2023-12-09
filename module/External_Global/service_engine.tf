## Work around to handle IAP flag being set in backend when not compatible with Service-Extension
resource "local_file" "service_extension" {
  count = local.create_se_waf_traffic_extension ? 1 : 0

  content  = jsonencode(local.service_extension_spec)
  filename = format("%s/.staging/%s_service_extension.json", path.module, "glbl")

  depends_on = [
    google_compute_instance.gce_se_waf,
    google_compute_health_check.gce_se_waf_hc,
    google_compute_instance_group.gce_se_waf_ig,
    local_file.backend_service,
    null_resource.backend_service_create,
  ]
}

resource "null_resource" "service_extension_create" {
  count = local.create_se_waf_traffic_extension ? 1 : 0

  triggers = {
    filename = local_file.service_extension[0].filename
    name     = local.service_extension_spec.name
  }

  lifecycle {
    replace_triggered_by = [
      local_file.service_extension,
      local_file.backend_service,
    ]
  }

  provisioner "local-exec" {
    when    = create
    command = "gcloud beta service-extensions lb-traffic-extensions import  ${self.triggers.name} --source=${self.triggers.filename} --location=global --quiet"
  }


  depends_on = [
    google_compute_instance.gce_se_waf,
    google_compute_health_check.gce_se_waf_hc,
    google_compute_instance_group.gce_se_waf_ig,
    local_file.backend_service,
    null_resource.backend_service_create,
    local_file.service_extension,
  ]
}


resource "null_resource" "service_extension_destroy" {
  count = local.create_se_waf_traffic_extension ? 1 : 0

  triggers = {
    filename = local_file.service_extension[0].filename
    name     = local.service_extension_spec.name
  }

  lifecycle {
    replace_triggered_by = [
      null_resource.backend_service_destroy,
    ]
  }

  provisioner "local-exec" {
    when    = destroy
    command = "gcloud beta service-extensions lb-traffic-extensions delete --location=global ${self.triggers.name} --quiet"
  }

  depends_on = [
    google_compute_instance.gce_se_waf,
    google_compute_health_check.gce_se_waf_hc,
    google_compute_instance_group.gce_se_waf_ig,
    null_resource.backend_service_create,
    local_file.backend_service,
    local_file.service_extension,
  ]
}
