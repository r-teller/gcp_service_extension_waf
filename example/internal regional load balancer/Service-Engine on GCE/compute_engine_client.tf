
resource "google_compute_instance" "gce_se_client" {
  for_each = toset(var.regions)

  project = var.project_id

  name = format("compute-engine-se-client-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
  zone = data.google_compute_zones.zones[each.key].names[0]

  metadata_startup_script = file("${path.module}/metadata_startup_scripts/compute_engine_client.sh")
  
  boot_disk {
    auto_delete = true

    initialize_params {
      image = "projects/debian-cloud/global/images/debian-11-bullseye-v20231115"
      size  = 10
      type  = "pd-balanced"
    }

    mode = "READ_WRITE"
  }

  labels = {
    goog-ec-src  = "vm_add-tf"
  }

  machine_type = "e2-small"

  network_interface {
    subnetwork = google_compute_subnetwork.subnetwork_rfc1918[each.key].self_link
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
    provisioning_model  = "STANDARD"
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = false
    enable_vtpm                 = true
  }

  depends_on = [google_compute_router_nat.nat]
}