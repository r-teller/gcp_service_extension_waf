variable "project_id" {
  type = string
}

variable "network" {
  type    = string
  default = null
}

variable "create_se_waf_backend_service" {
  type    = bool
  default = true
}

variable "create_se_waf_traffic_extension" {
  type    = bool
  default = true
}

variable "global_se_waf_env" {
  type = list(object({
    name  = string
    value = string
  }))

  default = [
    {
      name  = "se_debug",
      value = "False",
    },
    {
      name  = "se_require_iap",
      value = "False"
    },
    {
      "name" : "se_allowed_ipv4_cidr_ranges",
      "value" : "0.0.0.0/0"
    },
    {
      "name" : "se_denied_ipv4_cidr_ranges",
      "value" : ""
    }
  ]
}

variable "instance_configurations" {
  type = list(object({
    region         = string,
    zones          = optional(list(string), []),
    subnetwork     = string
    instance_count = optional(number, 1)
    machine_type   = optional(string, "n2-standard-2")
    container_id   = optional(string, "rteller/se-waf:0.0.4-beta"),
    se_waf_env = optional(list(object({
      name  = string
      value = string
    })), null)
  }))

  validation {
    condition     = alltrue([for region in distinct(var.instance_configurations.*.region) : can(regex("^[a-z]+-[a-z]+[0-9]$", region))])
    error_message = "One or more regions in the instance_configurations may not be known valid GCP regions."
  }

  validation {
    condition     = length(distinct(flatten(var.instance_configurations.*.zones))) == length(flatten(var.instance_configurations.*.zones))
    error_message = "One or more specified zones may be duplicate."
  }

  validation {
    condition = alltrue([
      for region in [for configuration in var.instance_configurations : configuration.region if length(configuration.zones) == 0] :
      !anytrue([
        for zone in flatten(var.instance_configurations.*.zones) : strcontains(zone, region)
      ])
    ])
    error_message = "One or more specified zones may be overlaps with []."
  }

  validation {
    condition     = alltrue([for configuration in var.instance_configurations : can(regex(".*regions/${configuration.region}/.*", configuration.subnetwork))])
    error_message = "Each subnetwork in the instance_configurations must contain the corresponding region."
  }

  validation {
    condition     = alltrue(flatten([for configuration in var.instance_configurations : [for zone in configuration.zones : startswith(zone, configuration.region)] if length(configuration.zones) > 0]))
    error_message = "Each zone in the instance_configurations must contain the corresponding region."
  }
}

variable "forwarding_rules" {
  type = list(string)
}

variable "random_suffix" {
  type    = string
  default = null
}
