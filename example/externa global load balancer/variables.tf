variable "project_id" {
  type = string
}

variable "regions" {
  type    = list(string)
  default = ["us-central1"]
}
