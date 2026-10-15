# conftest policy against `terraform show -json plan.out` (NOT RUN in this submission; no conftest in sandbox).
package main

eu_regions := {"eu-central-1", "eu-west-1"}

deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "aws_db_instance"
  rc.change.after.tags.residency == "eu"
  not eu_regions[rc.change.after.availability_zone]
  msg := sprintf("%s: EU-tagged DB outside EU", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "aws_s3_bucket_replication_configuration"
  msg := sprintf("%s: S3 replication needs explicit residency review", [rc.address])
}
