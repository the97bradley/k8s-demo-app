provider "google" {
  project     = var.project_id
  region      = "us-central1"
  credentials = var.gcp_credentials
}

resource "google_container_cluster" "primary" {
  name     = "host-cluster"
  location = "us-central1-a"

  initial_node_count = 3  # Ensure cluster has nodes

  node_config {
    machine_type = "e2-medium"
  }

  # Prevent cluster destruction and recreation
  lifecycle {
    prevent_destroy = true
  }
}


resource "google_storage_bucket" "mongo-backups-bucket-k8s-project" {
  name          = "mongo-backups-bucket"
  location      = "US"
  uniform_bucket_level_access = true


  # Prevent bucket destruction and recreation
  lifecycle {
    prevent_destroy = true
  }
}
