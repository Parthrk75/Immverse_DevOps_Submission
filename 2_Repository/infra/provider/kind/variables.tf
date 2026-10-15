variable "name" {
  type    = string
  default = "local"
}
variable "region" {
  type    = string
  default = "local"
}
variable "dr_region" {
  type    = string
  default = "local"
}
variable "residency" {
  type    = string
  default = "local"
}
variable "size" {
  type    = string
  default = "s"
}
variable "tags" {
  type    = map(string)
  default = {}
}
