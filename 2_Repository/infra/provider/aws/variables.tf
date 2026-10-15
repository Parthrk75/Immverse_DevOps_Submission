variable "name" { type = string }
variable "region" { type = string }
variable "dr_region" { type = string }
variable "residency" {
  type = string
  validation {
    condition     = contains(["eu", "us"], var.residency)
    error_message = "residency must be eu or us."
  }
}
variable "size" {
  type    = string
  default = "m"
  validation {
    condition     = contains(["s", "m", "l"], var.size)
    error_message = "size must be s, m or l."
  }
}
variable "tags" {
  type    = map(string)
  default = {}
}
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
variable "kubernetes_version" {
  type    = string
  default = "1.31"
}
# Shared stack uses a larger DB ceiling; tenants use the preset.
variable "db_max_acu_override" {
  type    = number
  default = null
}
