


provider "google" {
  project     = var.project_id
  region      = "us-central1"
  credentials = var.gcp_credentials
}

terraform {
  backend "gcs" {
    bucket = "k8s-proj-state-file"
  }
}



resource "google_cloudfunctions_function" "mongo_backup_function" {
  name        = "mongo_backup_function"
  runtime     = "python39"
  entry_point = "backup_mongo"
  trigger_http = true
  source_archive_bucket =  "backup-function-code"
  source_archive_object =  "backup-func.zip"

  lifecycle {
    prevent_destroy = true
  }
}


