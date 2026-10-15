variable "name" { type = string }
variable "cloud" {
  type    = string
  default = "aws"
}
variable "region" { type = string }
variable "dr_region" { type = string }
variable "residency" { type = string }
variable "size" { type = string }
variable "ring" {
  type    = string
  default = "ring1-small"
}
variable "remote_write_url" {
  type    = string
  default = ""
}
