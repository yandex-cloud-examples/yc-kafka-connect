# Infrastructure for Yandex Cloud Managed Service for Apache Kafka® clusters with Kafka Connect
#
# RU: https://yandex.cloud/ru/docs/managed-kafka/tutorials/kafka-connect
# EN: https://yandex.cloud/en/docs/managed-kafka/tutorials/kafka-connect
#
# Configure the parameters of the Managed Service for Apache Kafka® cluster and Virtual Machine:

locals {
  image_id        = "" # Public image ID from https://yandex.cloud/en/docs/compute/operations/images-with-pre-installed-software/get-list
  vm_username     = "" # Username to connect to the routing VM via SSH. Images with Ubuntu Linux use the `ubuntu` username by default.
  vm_ssh_key_path = "" # Path to the SSH public key for the routing VM. Example: "~/.ssh/key.pub".
  kf_password     = "" # Password for the username "user" in Managed Service for Apache Kafka® cluster

  # The following settings are predefined. Change them only if necessary.
  network_name    = "kafka-connect-network" # Name of the network
  subnet_name     = "kafka-subnet-a"        # Name of the subnet
  vm_name         = "vm-ubuntu-20-04"       # Name of the Virtual Machine
  kf_cluster_name = "kafka-connect-cluster" # Name of the Apache Kafka® cluster
  kf_topic        = "messages"              # Name of the Apache Kafka® topic
  kf_username     = "user"                  # Username of the Apache Kafka® cluster
}

# Network infrastructure

resource "yandex_vpc_network" "kafka-connect-network" {
  description = "Network for the Managed Service for Apache Kafka® cluster"
  name        = local.network_name
}

resource "yandex_vpc_subnet" "subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone"
  name           = local.subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.kafka-connect-network.id
  v4_cidr_blocks = ["10.1.0.0/24"]
}

resource "yandex_vpc_default_security_group" "kafka-connect-security-group" {
  description = "Security group for the Managed Service for Apache Kafka® cluster"
  network_id  = yandex_vpc_network.kafka-connect-network.id

  ingress {
    description    = "Allow connections to the Managed Service for Apache Kafka® broker hosts from the Internet"
    protocol       = "TCP"
    port           = 9091
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow connections to the Managed Service for Apache Kafka® schema registry from the Internet"
    protocol       = "TCP"
    port           = 9440
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow SSH connections to VM from the Internet"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allow outgoing connections to any required resource"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# VM infrastructure

resource "yandex_compute_instance" "vm-ubuntu-20-04" {
  description = "Virtual Machine with Ubuntu 20.04"
  name        = local.vm_name
  platform_id = "standard-v1"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2 # GB
  }

  boot_disk {
    initialize_params {
      image_id = local.image_id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet-a.id
    nat                = true
    security_group_ids = [yandex_vpc_default_security_group.kafka-connect-security-group.id]
  }

  metadata = {
    # Set username and path for the SSH public key
    # Images with Ubuntu Linux use the `ubuntu` username by default
    ssh-keys = "${local.vm_username}:${file(local.vm_ssh_key_path)}"
  }
}

# Infrastructure for the Managed Service for Apache Kafka® cluster

resource "yandex_mdb_kafka_cluster" "kafka-connect-cluster" {
  description        = "Managed Service for Apache Kafka® cluster"
  environment        = "PRODUCTION"
  name               = local.kf_cluster_name
  network_id         = yandex_vpc_network.kafka-connect-network.id
  security_group_ids = [yandex_vpc_default_security_group.kafka-connect-security-group.id]

  config {
    assign_public_ip = true
    brokers_count    = 1
    version          = "2.8"
    kafka {
      resources {
        disk_size          = 10 # GB
        disk_type_id       = "network-ssd"
        resource_preset_id = "s2.micro"
      }
    }

    zones = [
      "ru-central1-a"
    ]
  }

  depends_on = [
    yandex_vpc_subnet.subnet-a
  ]
}

# Topic of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_topic" "messages" {
  cluster_id         = yandex_mdb_kafka_cluster.kafka-connect-cluster.id
  name               = local.kf_topic
  partitions         = 1
  replication_factor = 1
}

# User of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_user" "user" {
  cluster_id = yandex_mdb_kafka_cluster.kafka-connect-cluster.id
  name       = local.kf_username
  password   = local.kf_password
  permission {
    topic_name = yandex_mdb_kafka_topic.messages.name
    role       = "ACCESS_ROLE_CONSUMER"
  }
  permission {
    topic_name = yandex_mdb_kafka_topic.messages.name
    role       = "ACCESS_ROLE_PRODUCER"
  }
}
