# data "google_compute_zones" "zones" {
#   for_each = { for configuration in var.instance_configurations : configuration.region => "" if length(configuration.zones) == 0 }

#   project = var.project_id
#   region  = each.key
# }

# resource "null_resource" "name" {
#   for_each = { for x in local.instance_configurations : format("%s%s%s", x.idx, x.zone, "random_id.suffix.hex") => x }
# }

locals {
  create_se_waf_backend_service   = alltrue([var.create_se_waf_backend_service, length(google_compute_instance_group.gce_se_waf_ig) > 0])
  create_se_waf_traffic_extension = alltrue([var.create_se_waf_traffic_extension, local.create_se_waf_backend_service])

  random_suffix = try(var.random_suffix, random_id.suffix.hex)

  instance_configurations = { for instance in flatten([
    for configuration in var.instance_configurations : [
      for idx in range(configuration.instance_count) : {
        idx          = idx
        zone         = length(configuration.zones) > 0 ? configuration.zones[idx % length(configuration.zones)] : data.google_compute_zones.zones[configuration.region].names[(idx % length(data.google_compute_zones.zones[configuration.region].names))]
        subnetwork   = configuration.subnetwork
        container_id = configuration.container_id
        machine_type = configuration.machine_type
        env = [
          {
            name = "se_debug",
            value = tostring(coalesce(
              try(configuration.se_waf_env.se_debug, null),
              var.global_se_waf_env.se_debug,
            ))
          },
          {
            name = "se_require_iap",
            value = tostring(coalesce(
              try(configuration.se_waf_env.se_require_iap, null),
              var.global_se_waf_env.se_require_iap,
            ))
          },
          {
            name = "se_allowed_ipv4_cidr_ranges",
            value = try(join(",", coalesce(
              try(configuration.se_waf_env.se_allowed_ipv4_cidr_ranges, null),
              var.global_se_waf_env.se_allowed_ipv4_cidr_ranges,
            )), "")
          },
          {
            name = "se_denied_ipv4_cidr_ranges",
            value = try(join(",", coalesce(
              try(configuration.se_waf_env.se_denied_ipv4_cidr_ranges, null),
              var.global_se_waf_env.se_denied_ipv4_cidr_ranges,
            )), "")
          }
        ]
      }
    ]
    ]) : format("gce-cos-se-waf-%s-%02d", instance.zone, instance.idx) => merge(instance, {
    name = format(
      "gce-cos-se-waf-%s-%02d-%s",
      templatefile("${path.module}/templates/zone.tftpl", {
        zone = instance.zone
      }),
      instance.idx,
      local.random_suffix
    )
    })
  }

  backend_service_spec = {
    "name" : format("l7-xlb-se-waf-bs-%s-%s", "glbl", local.random_suffix),
    "affinityCookieTtlSec" : 0,
    "backends" : [for instanceGroup in google_compute_instance_group.gce_se_waf_ig :
      {
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
      try(google_compute_health_check.gce_se_waf_hc[0].id, null)
    ],
    "loadBalancingScheme" : "EXTERNAL_MANAGED",
    "localityLbPolicy" : "ROUND_ROBIN",
    "portName" : "grpc",
    "protocol" : "HTTP2",
    "sessionAffinity" : "NONE",
    "timeoutSec" : 30
  }

  service_extension_spec = {
    name                = format("l7-xlb-se-waf-te-%s-%s", "glbl", local.random_suffix)
    forwardingRules     = var.forwarding_rules
    loadBalancingScheme = "EXTERNAL_MANAGED"
    extensionChains = [
      {
        name           = "chain-1"
        matchCondition = { celExpression = "request.path.startsWith('/') && !request.path.endsWith('.css') && !request.path.endsWith('/favicon.ico')" }
        extensions = [
          {
            name      = "extension-1"
            authority = "demo.com",
            forwardHeaders = [
              ":method",
              ":scheme",
              ":authority",
              ":path",
              "x-forwarded-for",
              "x-forwarded-for-test",
              "x-goog-iap-jwt-assertion",
              "x-goog-iap-jwt-assertion-test"
            ],
            service  = format("https://www.googleapis.com/compute/v1/projects/%s/global/backendServices/%s", var.project_id, local.backend_service_spec.name)
            failOpen = false
            timeout  = "0.2s"
            supportedEvents = [
              "REQUEST_HEADERS"
            ]
          }
        ]
      }
    ]
  }
}
