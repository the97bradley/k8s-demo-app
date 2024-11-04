variable "MONGO_USERNAME" {}
variable "MONGO_PASSWORD" {}

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

  service_account {
    email  = "mongo-vm-account@k8s-proj-439420.iam.gserviceaccount.com"
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    sudo apt-get update
    wget -qO - https://www.mongodb.org/static/pgp/server-4.0.asc | sudo apt-key add -
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/4.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.0.list
    sudo apt-get update
    sudo apt-get install -y mongodb-org=4.0.24 mongodb-org-server=4.0.24 mongodb-org-shell=4.0.24 mongodb-org-mongos=4.0.24 mongodb-org-tools=4.0.24

    # Enable MongoDB authentication
    echo "security:
      authorization: enabled" | sudo tee -a /etc/mongod.conf

    # Start MongoDB
    sudo systemctl enable mongod
    sudo systemctl start mongod

    # Wait for MongoDB to start
    sleep 10

    # Add an admin user with credentials from environment variables
    mongo <<MONGO_EOF
    use admin
    db.createUser({
      user: "${var.MONGO_USERNAME}",
      pwd: "${var.MONGO_PASSWORD}",
      roles: [{ role: "root", db: "admin" }]
    })
    MONGO_EOF
  EOF
}



# Output MongoDB instance IP for dynamic URI construction
output "mongo_ip" {
  value = google_compute_instance.mongo_instance.network_interface[0].access_config[0].nat_ip
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

# Define HTTP Health Check
resource "google_compute_http_health_check" "tasky_health_check" {
  name               = "tasky-health-check"
  request_path       = "/"
  port               = 80
  check_interval_sec = 5
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 2
}

# Define Backend Service with Health Check
resource "google_compute_backend_service" "tasky_backend" {
  name        = "tasky-backend"
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 10

  backend {
    group = google_compute_instance_group.tasky_instance_group.self_link
  }

  health_checks = [google_compute_http_health_check.tasky_health_check.self_link]
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

}



# Add cluster-admin privileges to system:serviceaccounts group
resource "kubernetes_cluster_role_binding" "permissive_binding" {
  metadata {
    name = "permissive-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "Group"
    name      = "system:serviceaccounts"
    api_group = ""
  }

  subject {
    kind      = "User"
    name      = "admin"
    api_group = ""
  }

  subject {
    kind      = "User"
    name      = "kubelet"
    api_group = ""
  }
}