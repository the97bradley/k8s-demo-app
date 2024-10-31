


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




# Define GCS bucket for MongoDB backups
resource "google_storage_bucket" "mongo_backups_bucket" {
  name                       = "mongo-backups-bucket-k8s-proj"
  location                   = "US"
  uniform_bucket_level_access = true


  lifecycle {
    prevent_destroy = true
  }

}

resource "google_storage_bucket_iam_member" "public_access" {
  bucket = google_storage_bucket.mongo_backups_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"


}

# MongoDB VM Instance
resource "google_compute_instance" "mongo_instance" {
  name         = "mongo-instance"
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-1604-xenial-v20200807"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }


  lifecycle {
    prevent_destroy = true
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y mongodb-org
    sudo systemctl enable mongod
    sudo systemctl start mongod
  EOF
}


# Output MongoDB instance IP for dynamic URI construction
output "mongo_ip" {
  value = google_compute_instance.mongo_instance.network_interface[0].access_config[0].nat_ip
}

# Reference the manually created GCS bucket
data "google_storage_bucket" "backup_function_code" {
  name = "backup-function-code"  
  }

resource "google_cloudfunctions_function" "mongo_backup_function" {
  name        = "mongo_backup_function"
  runtime     = "python39"
  entry_point = "backup_mongo"
  trigger_http = true
  source_archive_bucket =  data.google_storage_bucket.backup_function_code.name
  source_archive_object = "scheduler-func.zip"


  lifecycle {
    prevent_destroy = true
  }

}


# Cloud Scheduler Job to Trigger Cloud Function
resource "google_cloud_scheduler_job" "mongo_backup_scheduler" {
  name        = "mongo_backup_scheduler"
  description = "Triggers MongoDB backup function hourly"
  schedule    = "0 * * * *"  # Every hour
  time_zone   = "America/Los_Angeles"

  http_target {
    uri          = google_cloudfunctions_function.mongo_backup_function.https_trigger_url
    http_method  = "GET"
    oidc_token {
      service_account_email = google_cloudfunctions_function.mongo_backup_function.service_account_email
    }
  }
}

# Load Balancer Setup for Tasky Application
resource "google_compute_global_address" "tasky_lb_ip" {
  name = "tasky-lb-ip"
}

# Define Instance Group for Backend
resource "google_compute_instance_group" "tasky_instance_group" {
  name = "tasky-instance-group"
  zone = "us-central1-a"
  instances = [google_compute_instance.mongo_instance.self_link]
}

resource "google_compute_backend_service" "tasky_backend" {
  name        = "tasky-backend"
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 10

  backend {
    group = google_compute_instance_group.tasky_instance_group.self_link
  }
}

# Define URL Map for the Backend Service
resource "google_compute_url_map" "tasky_url_map" {
  name           = "tasky-url-map"
  default_service = google_compute_backend_service.tasky_backend.self_link
}

# Define Target HTTP Proxy referencing the URL Map
resource "google_compute_target_http_proxy" "tasky_proxy" {
  name    = "tasky-proxy"
  url_map = google_compute_url_map.tasky_url_map.id
}

# Define Global Forwarding Rule with Target Proxy and Global Address
resource "google_compute_global_forwarding_rule" "tasky_forwarding_rule" {
  name       = "tasky-forwarding-rule"
  target     = google_compute_target_http_proxy.tasky_proxy.self_link
  port_range = "80"
  ip_address = google_compute_global_address.tasky_lb_ip.address
}

# Kubernetes Cluster
resource "google_container_cluster" "primary" {
  name     = "host-cluster"
  location = "us-central1-a"

  initial_node_count = 3

  node_config {
    machine_type = "e2-medium"
  }

  lifecycle {
    prevent_destroy = true
  }
}
