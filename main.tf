# Main Terraform Configuration File with Security Best Practices

provider "google" {
  project = var.project_id
  region  = var.region
}

# Network Configuration
resource "google_compute_network" "dvwa_network" {
  name = "dvwa-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "dvwa_subnetwork" {
  name          = "dvwa-subnetwork"
  network       = google_compute_network.dvwa_network.id
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
}

resource "google_compute_firewall" "dvwa_firewall" {
  name    = "dvwa-allow-https"
  network = google_compute_network.dvwa_network.name

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["dvwa-web"]
}

resource "google_compute_firewall" "dvwa_internal" {
  name    = "dvwa-allow-internal"
  network = google_compute_network.dvwa_network.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  source_ranges = ["10.0.0.0/24"]
}

# Compute Instance for DVWA
resource "google_compute_instance" "dvwa_instance" {
  name         = "dvwa-instance"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["dvwa-web"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork   = google_compute_subnetwork.dvwa_subnetwork.name
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update && apt-get install -y apache2 php php-mysql mysql-client git ufw fail2ban unattended-upgrades openssl

    # Secure Linux Configuration
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 443/tcp
    ufw enable

    echo "- Configure automatic security updates -"
    dpkg-reconfigure -f noninteractive unattended-upgrades

    echo "- Setup fail2ban for SSH protection -"
    cat <<FAIL2BAN > /etc/fail2ban/jail.local
    [sshd]
    enabled = true
    port = ssh
    logpath = /var/log/auth.log
    maxretry = 5
    FAIL2BAN
    systemctl restart fail2ban

    # Clone DVWA repository
    git clone https://github.com/digininja/DVWA.git /var/www/html
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html

    # Enable SSL modules and create self-signed certificate
    a2enmod ssl
    mkdir -p /etc/apache2/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/apache2/ssl/apache-selfsigned.key \
      -out /etc/apache2/ssl/apache-selfsigned.crt \
      -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=localhost"

    # Configure default SSL site
    cat <<EOF > /etc/apache2/sites-available/default-ssl.conf
    <IfModule mod_ssl.c>
      <VirtualHost *:443>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/html

        SSLEngine on
        SSLCertificateFile /etc/apache2/ssl/apache-selfsigned.crt
        SSLCertificateKeyFile /etc/apache2/ssl/apache-selfsigned.key

        <FilesMatch "\.(cgi|shtml|phtml|php)$">
          SSLOptions +StdEnvVars
        </FilesMatch>
        <Directory /usr/lib/cgi-bin>
          SSLOptions +StdEnvVars
        </Directory>

        ErrorLog /var/log/apache2/error.log
        CustomLog /var/log/apache2/access.log combined

      </VirtualHost>
    </IfModule>
    EOF

    a2ensite default-ssl.conf

    # Restart Apache to apply changes
    systemctl restart apache2
  EOT
}

# Health Check for Load Balancer
resource "google_compute_health_check" "dvwa_health" {
  name = "dvwa-health-check"

  http_health_check {
    request_path = "/"
    port         = 443
  }
}

# HTTPS Load Balancer and SSL Configuration
resource "google_compute_managed_ssl_certificate" "dvwa_ssl_cert" {
  name = "dvwa-ssl-cert"
  managed {
    domains = [var.domain_name]
  }
}

resource "google_compute_global_address" "dvwa_ip" {
  name = "dvwa-ip"
}

resource "google_compute_backend_service" "dvwa_backend" {
  name          = "dvwa-backend"
  health_checks = [google_compute_health_check.dvwa_health.self_link]
  enable_cdn    = true
  timeout_sec   = 10
  protocol      = "HTTPS"
}

resource "google_compute_url_map" "dvwa_url_map" {
  name            = "dvwa-url-map"
  default_service = google_compute_backend_service.dvwa_backend.self_link
}

resource "google_compute_target_https_proxy" "dvwa_https_proxy" {
  name            = "dvwa-https-proxy"
  ssl_certificates = [google_compute_managed_ssl_certificate.dvwa_ssl_cert.self_link]
  url_map         = google_compute_url_map.dvwa_url_map.self_link
}

resource "google_compute_global_forwarding_rule" "dvwa_forwarding_rule" {
  name       = "dvwa-https"
  target     = google_compute_target_https_proxy.dvwa_https_proxy.self_link
  port_range = "443"
  ip_address = google_compute_global_address.dvwa_ip.address
}

# Cloud Armor for DDoS Protection
resource "google_compute_security_policy" "dvwa_security_policy" {
  name        = "dvwa-security-policy"
  description = "Cloud Armor policy for DVWA"

  rule {
    priority = 1000
    action   = "deny"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = var.source_ip_ranges
      }
    }
  }

  rule {
    priority = 2147483647
    action   = "allow"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = true
      rule_visibility = "STANDARD"
    }
  }
}

# Logging and Monitoring Integration
resource "google_logging_metric" "dvwa_http_traffic" {
  name   = "dvwa-http-traffic"
  filter = "resource.type=\"global\" AND logName=\"projects/${var.project_id}/logs/requests\" AND httpRequest.status=200"
}

resource "google_monitoring_alert_policy" "dvwa_alert_policy" {
  combiner     = "OR"
  display_name = "DVWA Traffic Spike Alert"

  conditions {
    display_name = "Traffic Spike Condition"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/dvwa-http-traffic\" AND resource.type=\"global\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1000
      duration        = "120s"
    }
  }

  notification_channels = ["projects/${var.project_id}/notificationChannels/ID_Add"]
}

