terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

variable "token_ya" {
  type = string
  description = "**********************"
}

variable "cloud_id_ya" {
  type = string
  description = "**************************"
}

variable "folder_id_ya" {
  type = string
  description = "*********************"
}

variable "image_id_ya" {
  type = string
  description = "fd8pvhn48v88lqteokn6"
}

provider "yandex" {
  token     = "${var.token_ya}"
  cloud_id  = "${var.cloud_id_ya}"
  folder_id = "${var.folder_id_ya}"
}

# -----Сеть-----
resource "yandex_vpc_network" "network-1" {
  name = "network1"
}

resource "yandex_vpc_subnet" "subnet-1" {
  name           = "subnet1"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network-1.id
  route_table_id = yandex_vpc_route_table.rt.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_subnet" "subnet-2" {
  name           = "subnet2"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.network-1.id
  route_table_id = yandex_vpc_route_table.rt.id
  v4_cidr_blocks = ["192.168.20.0/24"]
}

resource "yandex_vpc_subnet" "subnet-3" {
  name           = "subnet3"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network-1.id
  route_table_id = yandex_vpc_route_table.rt.id
  v4_cidr_blocks = ["192.168.30.0/24"]
}

resource "yandex_vpc_gateway" "nat_gateway" {
  name = "nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "rt" {
  name       = "nat-route-table"
  network_id = yandex_vpc_network.network-1.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}

# -----Target Group-----
resource "yandex_alb_target_group" "target-group" {
  name      = "target-group"

  target {
    subnet_id = "${yandex_vpc_subnet.subnet-1.id}"
    ip_address   = "${yandex_compute_instance.web-server1.network_interface.0.ip_address}"
  }

  target {
    subnet_id = "${yandex_vpc_subnet.subnet-2.id}"
    ip_address   = "${yandex_compute_instance.web-server2.network_interface.0.ip_address}"
  }
}

# -----Backend Group-----
resource "yandex_alb_backend_group" "backend-group" {
  name      = "backend-group"

  http_backend {
    name = "http-backend"
    weight = 1
    port = 80
    target_group_ids = ["${yandex_alb_target_group.target-group.id}"]
    healthcheck {
      timeout = "10s"
      interval = "2s"
      healthy_threshold = 10
      unhealthy_threshold = 15
      http_healthcheck {
        path  = "/"
      }
    }
  }
}

# -----HTTP Router-----
resource "yandex_alb_http_router" "http-router" {
  name      = "http-router"
}

resource "yandex_alb_virtual_host" "virtual-host" {
  name      = "virtual-host"
  http_router_id = yandex_alb_http_router.http-router.id
  route {
    name = "route"

    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.backend-group.id
        timeout = "60s"
      }
    }
  }
}

# -----Application Load Balancer-----
resource "yandex_alb_load_balancer" "load-balancer" {
  name        = "load-balancer"

  network_id  = yandex_vpc_network.network-1.id
  security_group_ids = [yandex_vpc_security_group.security-public-alb.id]

  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.subnet-1.id
    }

    location {
      zone_id   = "ru-central1-b"
      subnet_id = yandex_vpc_subnet.subnet-2.id
    }
  }

  listener {
    name = "listener"
    endpoint {
      address {
        external_ipv4_address {
        }
      }
      ports = [ 80 ]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.http-router.id
      }
    }
  }
}

# -----Security Bastion Host-----
resource "yandex_vpc_security_group" "security-bastion-host" {
  name        = "security-bastion-host"
  network_id  = yandex_vpc_network.network-1.id
  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----Security SSH Traffic-----
resource "yandex_vpc_security_group" "security-ssh-traffic" {
  name        = "security-ssh-traffic"
  network_id  = yandex_vpc_network.network-1.id
  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  ingress {
    protocol       = "ICMP"
    v4_cidr_blocks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }
}

# -----Security WebServers-----
resource "yandex_vpc_security_group" "security-webservers" {
  name        = "security-webservers"
  network_id  = yandex_vpc_network.network-1.id

  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  ingress {
    protocol       = "TCP"
    port           = 4040
    v4_cidr_blocks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  ingress {
    protocol       = "TCP"
    port           = 9100
    v4_cidr_blocks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----Security Prometheus-----
resource "yandex_vpc_security_group" "security-prometheus" {
  name        = "security-prometheus"
  network_id  = yandex_vpc_network.network-1.id

  ingress {
    protocol       = "TCP"
    port           = 9090
    v4_cidr_blocks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  ingress {
    protocol       = "TCP"
    port           = 9100
    v4_cidr_blocks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----Security Public Grafana-----
resource "yandex_vpc_security_group" "security-public-grafana" {
  name        = "security-public-grafana"
  network_id  = yandex_vpc_network.network-1.id

  ingress {
    protocol       = "TCP"
    port           = 3000
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 9100
    v4_cidr_blocks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----Security ElasticSearch-----
resource "yandex_vpc_security_group" "security-elasticsearch" {
  name        = "security-elasticsearch"
  network_id  = yandex_vpc_network.network-1.id

  ingress {
    protocol       = "TCP"
    port           = 9200
    v4_cidr_blocks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  ingress {
    protocol       = "TCP"
    port           = 9100
    v4_cidr_blocks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----Security Public Kibana-----
resource "yandex_vpc_security_group" "security-public-kibana" {
  name        = "security-public-kibana"
  network_id  = yandex_vpc_network.network-1.id

  ingress {
    protocol       = "TCP"
    port           = 5601
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 9100
    v4_cidr_blocks = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----Security Public Load Balancer-----
resource "yandex_vpc_security_group" "security-public-alb" {
  name        = "security-public-alb"
  network_id  = yandex_vpc_network.network-1.id

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----VM - Bastion Host-----
resource "yandex_compute_instance" "bastion-host" {

  name = "bastion-host"
  hostname = "bastion-host"
  zone = "ru-central1-a"

  resources {
    cores = 2
    memory = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = "${var.image_id_ya}"
      size = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-3.id
    nat       = true
    security_group_ids = [yandex_vpc_security_group.security-bastion-host.id]
  }

  metadata = {
    user-data = "${file("./main.yaml")}"
  }

  scheduling_policy {
    preemptible = true # Прерываемая ВМ
  }
}

# -----VM - Web-Server1-----
resource "yandex_compute_instance" "web-server1" {

  name = "web-server1"
  hostname = "web-server1"
  zone = "ru-central1-a"

  resources {
    cores = 2
    memory = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = "${var.image_id_ya}"
      size = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = false
    security_group_ids = [yandex_vpc_security_group.security-ssh-traffic.id, yandex_vpc_security_group.security-webservers.id]
  }

  metadata = {
    user-data = "${file("./main.yaml")}"
  }
}

# -----VM - Web-Server2-----
resource "yandex_compute_instance" "web-server2" {

  name = "web-server2"
  hostname = "web-server2"
  zone = "ru-central1-b"

  resources {
    cores  = 2
    memory = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = "${var.image_id_ya}"
      size = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-2.id
    nat       = false
    security_group_ids = [yandex_vpc_security_group.security-ssh-traffic.id, yandex_vpc_security_group.security-webservers.id]
  }

  metadata = {
    user-data = "${file("./main.yaml")}"
  }
}

# -----VM - Prometheus-----
resource "yandex_compute_instance" "prometheus" {

  name = "prometheus"
  hostname = "prometheus"
  zone = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = "${var.image_id_ya}"
      size = 15
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-3.id
    nat       = false
    security_group_ids = [yandex_vpc_security_group.security-ssh-traffic.id, yandex_vpc_security_group.security-prometheus.id]
  }

  metadata = {
    user-data = "${file("./main.yaml")}"
  }
}

# -----VM - Grafana-----
resource "yandex_compute_instance" "grafana" {

  name = "grafana"
  hostname = "grafana"
  zone = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = "${var.image_id_ya}"
      size = 10
    }
  }


  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-3.id
    nat       = true
    security_group_ids = [yandex_vpc_security_group.security-public-grafana.id, yandex_vpc_security_group.security-ssh-traffic.id]
  }

  metadata = {
    user-data = "${file("./main.yaml")}"
  }
}

# -----VM - ElasticSearch-----
resource "yandex_compute_instance" "elasticsearch" {

  name = "elasticsearch"
  hostname = "elasticsearch"
  zone = "ru-central1-a"

  resources {
    cores  = 2
    memory = 4
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = "${var.image_id_ya}"
      size = 15
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-3.id
    nat       = false
    security_group_ids = [yandex_vpc_security_group.security-elasticsearch.id, yandex_vpc_security_group.security-ssh-traffic.id]
  }

  metadata = {
    user-data = "${file("./main.yaml")}"
  }
}

# -----VM - Kibana-----
resource "yandex_compute_instance" "kibana" {

  name = "kibana"
  hostname = "kibana"
  zone = "ru-central1-a"

  resources {
    cores  = 2
    memory = 4
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = "${var.image_id_ya}"
      size = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-3.id
    nat       = true
    security_group_ids = [yandex_vpc_security_group.security-public-kibana.id, yandex_vpc_security_group.security-ssh-traffic.id]
  }

  metadata = {
    user-data = "${file("./main.yaml")}"
  }
}

# -----Snapshot all VM-----
resource "yandex_compute_snapshot_schedule" "default" {
  name           = "snapshot"

  schedule_policy {
  expression = "0 0 * * *"
  }

  snapshot_count = 7
  retention_period = "24h"

  snapshot_spec {
    description = "snapshot-description"
    labels = {
      snapshot-label = "my-snapshot-label-value"
    }
  }

  labels = {
    my-label = "my-label-value"
  }

  disk_ids = [yandex_compute_instance.bastion-host.boot_disk.0.disk_id,
              yandex_compute_instance.web-server1.boot_disk.0.disk_id,
              yandex_compute_instance.web-server2.boot_disk.0.disk_id,
              yandex_compute_instance.prometheus.boot_disk.0.disk_id,
              yandex_compute_instance.grafana.boot_disk.0.disk_id,
              yandex_compute_instance.elasticsearch.boot_disk.0.disk_id,
              yandex_compute_instance.kibana.boot_disk.0.disk_id]
}
