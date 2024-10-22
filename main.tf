provider "google" {
  project     = var.project_id
  region      = "us-central1"
  credentials = var.gcp_credentials
}

resource "google_container_cluster" "primary" {
  name     = "wiz-cluster"
  location = "us-central1-a"

  initial_node_count = 3  # Ensure cluster has nodes

  node_config {
    machine_type = "e2-medium"
  }
}


resource "google_storage_bucket" "mongo-backups" {
  name          = "mongo-backup-bucket"
  location      = "US"
  uniform_bucket_level_access = true
}
