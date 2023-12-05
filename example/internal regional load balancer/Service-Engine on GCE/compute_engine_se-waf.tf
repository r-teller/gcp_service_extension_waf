
resource "google_compute_instance" "gce_se_waf" {
  for_each = toset(var.regions)

  project = var.project_id

  name = format("compute-engine-se-waf-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
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
            "image" : "rteller/se-waf:0.0.4-beta",
            "env" : [
              {
                "name" : "se_debug",
                "value" : "True"
              },
              {
                "name" : "se_allowed_ipv4_cidr_ranges",
                "value" : "1.1.1.1/32,1.1.1.2/32,0.0.0.0/0"
              },
              {
                "name" : "se_denied_ipv4_cidr_ranges",
                "value" : "1.0.0.0/8"
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

  name = format("health-check-se-waf-8000-%s", random_id.id.hex)
  http_health_check {
    port = 8000
  }
}

resource "google_compute_instance_group" "gce_se_waf_instance_group" {
  for_each = toset(var.regions)

  project = var.project_id

  name    = format("l7-ilb-se-waf-instance-group-%s-%s", module.gcp_utils.region_short_name_map[lower(each.key)], random_id.id.hex)
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
output "backend_service_json" {
  value = local.backend_service_json
}
locals {
  backend_service_json = { for key, value in google_compute_instance_group.gce_se_waf_instance_group : key => {
    "name" : format("l7-ilb-se-waf-backend-service-%s-%s", module.gcp_utils.region_short_name_map[lower(key)], random_id.id.hex, ),
    "affinityCookieTtlSec" : 0,
    "backends" : [
      {
        "balancingMode" : "UTILIZATION",
        "capacityScaler" : 1,
        "group" : value.self_link,
        "maxUtilization" : 0.8
      }
    ],
    "connectionDraining" : {
      "drainingTimeoutSec" : 300
    },
    "healthChecks" : [
      google_compute_health_check.gce_se_waf_hc.id
    ],
    "loadBalancingScheme" : "INTERNAL_MANAGED",
    "localityLbPolicy" : "ROUND_ROBIN",
    "portName" : "grpc",
    "protocol" : "HTTP2",
    "sessionAffinity" : "NONE",
    "timeoutSec" : 30
  } }

  service_extension_json = { for key, value in google_compute_instance_group.gce_se_waf_instance_group : key => {
    name = format("l7-ilb-echo-service-engine-waf-%s-%s", module.gcp_utils.region_short_name_map[lower(key)], random_id.id.hex)
    forwardingRules = [
      google_compute_forwarding_rule.gcr_echo_ilb_forwarding_80[key].self_link,
    ]
    loadBalancingScheme = "INTERNAL_MANAGED"
    extensionChains = [
      {
        name           = "chain-1"
        matchCondition = { celExpression = "request.path.startsWith('/')" }
        extensions = [
          {
            name      = "extension-1"
            authority = "demo.com"
            service   = format("https://www.googleapis.com/compute/v1/projects/%s/regions/%s/backendServices/%s", var.project_id, key, local.backend_service_json[key].name)
            failOpen  = false
            timeout   = "0.2s"
            supportedEvents = [
              "REQUEST_HEADERS"
            ]
          }
        ]
      }
    ]
  } }
  # backend_service_name = format("l7-ilb-se-waf-backend-service-%s", random_id.id.hex)
  # backend_service_json2 = yamlencode({
  #   "name" : local.backend_service_name,
  #   "affinityCookieTtlSec" : 0,
  #   "backends" : [for instanceGroup in google_compute_instance_group.gce_se_waf_instance_group : {
  #     "balancingMode" : "UTILIZATION",
  #     "capacityScaler" : 1,
  #     "group" : instanceGroup.self_link,
  #     "maxUtilization" : 0.8
  #     }
  #   ],
  #   "connectionDraining" : {
  #     "drainingTimeoutSec" : 300
  #   },
  #   "healthChecks" : [
  #     google_compute_health_check.gce_se_waf_hc.id
  #   ],
  #   "loadBalancingScheme" : "INTERNAL_MANAGED",
  #   "localityLbPolicy" : "ROUND_ROBIN",
  #   "portName" : "grpc",
  #   "protocol" : "HTTP2",
  #   "sessionAffinity" : "NONE",
  #   "timeoutSec" : 30
  # })

  # service_extension_name = format("l7-xlb-echo-service-engine-waf-%s", random_id.id.hex)
  # service_extension_yaml = yamlencode({
  #   name = local.service_extension_name
  #   forwardingRules = [
  #     for forwarding_rule in google_compute_forwarding_rule.gcr_echo_ilb_forwarding_80 : forwarding_rule.self_link
  #   ]
  #   loadBalancingScheme = "INTERNAL_MANAGED"
  #   extensionChains = [
  #     {
  #       name           = "chain-1"
  #       matchCondition = { celExpression = "request.path.startsWith('/')" }
  #       extensions = [
  #         {
  #           name      = "extension-1"
  #           authority = "demo.com"
  #           service   = format("https://www.googleapis.com/compute/v1/projects/%s/global/backendServices/%s", var.project_id, local.backend_service_name)
  #           failOpen  = false
  #           timeout   = "0.2s"
  #           supportedEvents = [
  #             "REQUEST_HEADERS"
  #           ]
  #         }
  #       ]
  #     }
  #   ]
  # })
}

### Work around to handle IAP flag being set in backend when not compatible with Service-Extension
resource "local_file" "backend_service_yaml" {
  for_each = local.backend_service_json

  content  = yamlencode(each.value)
  filename = format("%s/.staging/%s_backend_service.yaml", path.module, each.key)

  provisioner "local-exec" {
    when    = create
    command = "gcloud compute backend-services import --region=${each.key} ${each.value.name} --source=${self.filename} --quiet"
  }
  depends_on = [google_compute_instance_group.gce_se_waf_instance_group]
}

resource "null_resource" "backend_service_yaml_destroy" {
  for_each = local.backend_service_json

  triggers = {
    name = each.value.name
  }

  provisioner "local-exec" {
    when    = destroy
    command = "gcloud compute backend-services delete --region=${each.key} ${self.triggers.name} --quiet"
  }

  depends_on = [local_file.backend_service_yaml]
}

## Work around to handle IAP flag being set in backend when not compatible with Service-Extension
resource "local_file" "service_extension_yaml" {
  for_each = local.service_extension_json

  content  = yamlencode(each.value)
  filename = format("%s/.staging/%s_service_extension.yaml", path.module, each.key)

  provisioner "local-exec" {
    when    = create
    command = "gcloud beta service-extensions lb-traffic-extensions import ${each.value.name} --source=${self.filename} --location=${each.key} --quiet"
  }

  depends_on = [local_file.backend_service_yaml, google_compute_instance_group.gce_se_waf_instance_group, null_resource.backend_service_yaml_destroy]
}

resource "null_resource" "service_extension_yaml_destroy" {
  for_each = local.service_extension_json

  triggers = {
    name = each.value.name
  }

  lifecycle {
    replace_triggered_by = [local_file.backend_service_yaml[each.key]]
  }

  provisioner "local-exec" {
    when    = destroy
    command = "gcloud beta service-extensions lb-traffic-extensions delete --location=${each.key} ${self.triggers.name} --quiet"
  }

  depends_on = [local_file.service_extension_yaml]
}

# resource "null_resource" "backend_service_yaml_destroy" {
#   triggers = {
#     name = local.backend_service_name
#   }

#   provisioner "local-exec" {
#     when    = destroy
#     command = "gcloud compute backend-services delete --global ${self.triggers.name} --quiet"
#   }

#   depends_on = [local_file.backend_service_yaml]
# }

# ## Work around to handle IAP flag being set in backend when not compatible with Service-Extension
# resource "local_file" "service_extension_yaml" {
#   content  = local.service_extension_yaml
#   filename = "${path.module}/.staging/service_extension.yaml"

#   provisioner "local-exec" {
#     when    = create
#     command = "gcloud beta service-extensions lb-traffic-extensions import ${local.service_extension_name} --source=${self.filename} --location=global --quiet"
#   }

#   depends_on = [local_file.backend_service_yaml, google_compute_instance_group.gce_se_waf_instance_group]
# }

# # resource "null_resource" "service_extension_yaml_destroy" {
# #   triggers = {
# #     name = local.service_extension_name
# #   }

# #   lifecycle {
# #     replace_triggered_by = [local_file.backend_service_yaml]
# #   }

# #   provisioner "local-exec" {
# #     when    = destroy
# #     command = "gcloud beta service-extensions lb-traffic-extensions delete --location=global ${self.triggers.name} --quiet"
# #   }

# #   depends_on = [local_file.service_extension_yaml]
# # }
