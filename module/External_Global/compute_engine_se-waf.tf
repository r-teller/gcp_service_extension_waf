data "google_compute_zones" "zones" {
  for_each = { for configuration in var.instance_configurations : configuration.region => "" if length(configuration.zones) == 0 }

  project = var.project_id
  region  = each.key
}

resource "null_resource" "gce_se_waf" {
  for_each = { for key, value in local.instance_configurations : key => value if var.gce_reset_on_env_change }

  triggers = {
    project_id = var.project_id
    name       = each.value.name
    zone       = each.value.zone
    env        = join("", each.value.env.*.value)
  }

  provisioner "local-exec" {
    when    = destroy
    command = "gcloud compute instances reset ${self.triggers.name} --zone ${self.triggers.zone} --project ${self.triggers.project_id}"
  }
  depends_on = [google_compute_instance.gce_se_waf, ]
}

resource "google_compute_instance" "gce_se_waf" {
  for_each = local.instance_configurations

  project = var.project_id

  name = each.value.name
  zone = each.value.zone

  boot_disk {
    auto_delete = true

    initialize_params {
      image = "projects/cos-cloud/global/images/cos-stable-109-17800-66-27"
      size  = 10
      type  = "pd-balanced"
    }

    mode = "READ_WRITE"
  }

  labels = {
    container-vm = "cos-stable-109-17800-66-27"
    goog-ec-src  = "vm_add-tf"
  }

  machine_type = each.value.machine_type

  metadata = {
    gce-container-declaration = yamlencode({
      "spec" : {
        "containers" : [
          {
            "name" : "instance-1",
            "image" : each.value.container_id,
            "env" : each.value.env,
            "stdin" : false,
            "tty" : false
          }
        ],
        "restartPolicy" : "Always"
      }
    })
  }

  network_interface {
    subnetwork = each.value.subnetwork
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
    provisioning_model  = "STANDARD"
  }

  service_account {
    scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append"
    ]
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = false
    enable_vtpm                 = true
  }

  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"]
    ]
  }
}

resource "google_compute_instance_group" "gce_se_waf_ig" {
  for_each = toset(distinct(values(local.instance_configurations).*.zone))

  project = var.project_id

  name = format("l7-xlb-se-waf-ig-%s-%s", templatefile("${path.module}/templates/zone.tftpl", {
    zone = each.key
  }), local.random_suffix)

  zone    = each.key
  network = var.network

  named_port {
    name = "grpc"
    port = 8443
  }

  instances = [
    for key, value in google_compute_instance.gce_se_waf : value.self_link if value.zone == each.key
  ]

  depends_on = [google_compute_instance.gce_se_waf]
}
