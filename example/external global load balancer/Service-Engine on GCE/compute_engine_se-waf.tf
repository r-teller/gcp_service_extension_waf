resource "google_compute_instance" "gce_se_waf" {
  for_each = toset(var.regions)

  project = var.project_id

  name = format("compute-engine-se-waf-%s", module.gcp_utils.region_short_name_map[lower(each.key)])
  zone = data.google_compute_zones.zones[each.key].names[0]

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

  machine_type = "n2-standard-2"

  metadata = {
    gce-container-declaration = yamlencode({
      "spec" : {
        "containers" : [
          {
            "name" : "instance-1",
            "image" : "rteller/se-waf:0.0.3-beta",
            "env" : [
              {
                "name" : "se_debug",
                "value" : "True"
              },
              {
                "name" : "se_allowed_ipv4_cidr_ranges",
                "value" : "1.1.1.1/32"
              }
            ],
            "stdin" : false,
            "tty" : false
          }
        ],
        "restartPolicy" : "Always"
      }
    })
  }


  network_interface {
    subnetwork = google_compute_subnetwork.subnetwork_rfc1918[each.key].self_link
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

  depends_on = [google_compute_router_nat.nat]
}


resource "google_compute_health_check" "gce_se_waf_hc" {
  project = var.project_id

  name = "health-check-se-waf-8000"
  http_health_check {
    port = 8000
  }
}

resource "google_compute_instance_group" "gce_se_waf_instance_group" {
  for_each = toset(var.regions)

  project = var.project_id

  name    = format("l7-xlb-se-waf-instance-group-%s", module.gcp_utils.region_short_name_map[lower(each.key)])
  zone    = data.google_compute_zones.zones[each.key].names[0]
  network = google_compute_network.vpc_network.id

  named_port {
    name = "grpc"
    port = 8443
  }

  instances = [
    for key, value in google_compute_instance.gce_se_waf : value.self_link if value.zone == data.google_compute_zones.zones[each.key].names[0]
  ]
}

locals {
  backend_service_name = "l7-xlb-se-waf-backend-service"
  backend_service_json = yamlencode({
    "name" : local.backend_service_name,
    "affinityCookieTtlSec" : 0,
    "backends" : [for instanceGroup in google_compute_instance_group.gce_se_waf_instance_group : {
      "balancingMode" : "UTILIZATION",
      "capacityScaler" : 1,
      "group" : instanceGroup.self_link,
      "maxUtilization" : 0.8
      }
    ],
    "connectionDraining" : {
      "drainingTimeoutSec" : 300
    },
    "healthChecks" : [
      google_compute_health_check.gce_se_waf_hc.id
    ],
    "loadBalancingScheme" : "EXTERNAL_MANAGED",
    "localityLbPolicy" : "ROUND_ROBIN",
    "portName" : "grpc",
    "protocol" : "HTTP2",
    "sessionAffinity" : "NONE",
    "timeoutSec" : 30
  })

  service_extension_name = "l7-xlb-echo-service-engine-waf"
  service_extension_yaml = yamlencode({
    name = local.service_extension_name
    forwardingRules = [
      google_compute_global_forwarding_rule.cloudrun_srv_echo_forwarding_80.self_link,
      google_compute_global_forwarding_rule.cloudrun_srv_echo_forwarding_443.self_link
    ]
    loadBalancingScheme = "EXTERNAL_MANAGED"
    extensionChains = [
      {
        name           = "chain-1"
        matchCondition = { celExpression = "request.path.startsWith('/')" }
        extensions = [
          {
            name      = "extension-1"
            authority = "demo.com"
            service   = format("https://www.googleapis.com/compute/v1/projects/%s/global/backendServices/%s", var.project_id, local.backend_service_name)
            failOpen  = false
            timeout   = "0.2s"
            supportedEvents = [
              "REQUEST_HEADERS"
            ]
          }
        ]
      }
    ]
  })
}

### Work around to handle IAP flag being set in backend when not compatible with Service-Extension
resource "local_file" "backend_service_yaml" {
  content  = local.backend_service_json
  filename = "${path.module}/.staging/backend_service.yaml"

  provisioner "local-exec" {
    when    = create
    command = "gcloud compute backend-services import --global ${local.backend_service_name} --source=${self.filename} --quiet"
  }
  depends_on = [google_compute_instance_group.gce_se_waf_instance_group]
}

resource "null_resource" "backend_service_yaml_destroy" {
  triggers = {
    name = local.backend_service_name
  }

  provisioner "local-exec" {
    when    = destroy
    command = "gcloud compute backend-services delete --global ${self.triggers.name} --quiet"
  }

  depends_on = [local_file.backend_service_yaml]
}

## Work around to handle IAP flag being set in backend when not compatible with Service-Extension
resource "local_file" "service_extension_yaml" {
  content  = local.service_extension_yaml
  filename = "${path.module}/.staging/service_extension.yaml"

  provisioner "local-exec" {
    when    = create
    command = "gcloud beta service-extensions lb-traffic-extensions import ${local.service_extension_name} --source=${self.filename} --location=global --quiet"
  }

  depends_on = [local_file.backend_service_yaml, google_compute_instance_group.gce_se_waf_instance_group]
}

resource "null_resource" "service_extension_yaml_destroy" {
  triggers = {
    name = local.service_extension_name
  }

  lifecycle {
    replace_triggered_by = [local_file.backend_service_yaml]
  }

  provisioner "local-exec" {
    when    = destroy
    command = "gcloud beta service-extensions lb-traffic-extensions delete --location=global ${self.triggers.name} --quiet"
  }

  depends_on = [local_file.service_extension_yaml]
}
