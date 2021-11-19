packer {
  required_version = "~> 1.7.3"

  required_plugins {
    amazon = {
      version = "=1.0.2-dev"
      source  = "github.com/AlexSc/amazon"
    }

    vagrant = {
      version = "~> 1"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

variable "region" {
  type        = string
  description = "AWS region to build AMIs in"
}

variable "environment" {
  type        = string
  description = "Value to be assigned to the Environment tag on created AMIs"
}

variable "cost_center" {
  type        = string
  default     = "packer"
  description = "Value to be assigned to the CostCenter tag on all temporary resources and created AMIs"
}

variable "instance_type" {
  type = map(string)
  default = {
    x86_64 = "m5.large"
    arm64  = "m6g.large"
  }
  description = "Instance type to use for building AMIs by architecture"
}

variable "ami_prefix" {
  type        = string
  description = "Prefix for uniquely generated AMI names"
}

variable "source_ami_owners" {
  type        = list(string)
  description = "A list of AWS account ids which may own AMIs that we use to run the root image builds."
  default     = ["self"]
}

variable "source_ami_name_prefix" {
  type        = string
  description = "The AMI name prefix for AMIs that we use to run the root image builds."
}

variable "ansible_playbook" {
  type        = string
  description = "Path to the ansible playbook used to provision the image. May be absolute or relative to the current working directory."
  default     = "playbooks/image.yml"
}

variable "volume_size" {
  type        = number
  description = "Size of the root volume in GB"
  default     = 2
}

data "amazon-parameterstore" "role_arn" {
  region = var.region

  name = "/teak/${var.environment}/ci-cd/packer_role_arn"
}

data "amazon-parameterstore" "instance_profile" {
  region = var.region

  name = "/teak/${var.environment}/ci-cd/instance_profile"
}

data "amazon-parameterstore" "local_vm_bucket" {
  region = var.region

  name = "/teak/${var.environment}/ci-cd/vm_bucket_id"
}

data "amazon-parameterstore" "ami_users" {
  region = var.region

  name = "/teak/${var.environment}/ci-cd/ami_consumers"
}

# Pull the latest root image
data "amazon-ami" "base_x86_64_debian_ami" {
  assume_role {
    role_arn = data.amazon-parameterstore.role_arn.value
  }

  filters = {
    virtualization-type = "hvm"
    name                = "${var.environment}-${var.source_ami_name_prefix}*"
    architecture        = "x86_64"
  }
  region      = var.region
  owners      = var.source_ami_owners
  most_recent = true
}

data "amazon-ami" "base_arm64_debian_ami" {
  assume_role {
    role_arn = data.amazon-parameterstore.role_arn.value
  }

  filters = {
    virtualization-type = "hvm"
    name                = "${var.environment}-${var.source_ami_name_prefix}*"
    architecture        = "arm64"
  }
  region      = var.region
  owners      = var.source_ami_owners
  most_recent = true
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  source_ami = {
    x86_64 = data.amazon-ami.base_x86_64_debian_ami.id
    arm64  = data.amazon-ami.base_arm64_debian_ami.id
  }
  role_arn = data.amazon-parameterstore.role_arn.value
  arch_map = { x86_64 = "amd64", arm64 = "arm64" }
}

source "amazon-ebs" "debian" {
  assume_role {
    role_arn = data.amazon-parameterstore.role_arn.value
  }

  subnet_filter {
    filters = {
      "tag:Application" : "Packer"
      "tag:Service" : "Build"
    }

    random = true
  }

  run_volume_tags = {
    Managed     = "packer"
    Environment = var.environment
    CostCenter  = var.cost_center
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  iam_instance_profile = data.amazon-parameterstore.instance_profile.value

  region        = var.region
  ebs_optimized = true
  ssh_username  = "admin"

  launch_block_device_mappings {
    volume_type = "gp3"
    # This relies on our source AMI providing an ami root device at /dev/xvda
    # We override the defaults with max free iops and max throughput for
    # gp3 volumes in order to minimize the time to copy the built image to
    # our fresh volume.
    device_name = "/dev/xvda"
    volume_size = var.volume_size
    iops        = 3000
    throughput  = 300

    delete_on_termination = true
  }

  # Scrub our gp3 preferences from the AMI.
  ami_block_device_mappings {
    volume_type = "gp3"
    device_name = "/dev/xvda"
    volume_size = var.volume_size
    iops        = 3000
    throughput  = 125

    delete_on_termination = true
  }

  ami_virtualization_type = "hvm"
  ami_users               = split(",", data.amazon-parameterstore.ami_users.value)
  ena_support             = true
  sriov_support           = true

  tags = {
    Application = "None"
    Environment = var.environment
    CostCenter  = var.cost_center
  }
}

source "vagrant" "debian" {
  source_path = "teak/bullseye64"
  provider    = "vmware_desktop"

  communicator = "ssh"
}

build {
  dynamic "source" {
    for_each = local.arch_map
    iterator = arch
    labels   = ["amazon-ebs.debian"]

    content {
      name          = "debian_${arch.key}"
      ami_name      = "${var.environment}-${var.ami_prefix}-${arch.key}-${local.timestamp}"
      instance_type = var.instance_type[arch.key]

      source_ami = local.source_ami[arch.key]

      run_tags = {
        Application = "ImageFactory"
        Environment = var.environment
        CostCenter  = var.cost_center
        Managed     = "packer"
        Service     = "${var.environment}-${var.ami_prefix}-${arch.key}-${local.timestamp}"
      }

      user_data = <<-EOT
      #cloud-config
      write_files:
        - content: |
            [Service]
            Environment="TEAK_SERVICE=${var.environment}-${var.ami_prefix}-${arch.key}-${local.timestamp}"
          path: /run/systemd/system/teak-.service.d/01_build_environment.conf
          owner: root:root
          permissions: '0644'
EOT
    }
  }

  source "vagrant.debian" {

  }

  provisioner "ansible" {
    playbook_file = abspath(var.ansible_playbook)
    extra_arguments = [
      "--extra-vars", "build_environment=${var.environment} region=${var.region} build_type=${source.type}"
    ]
    ansible_env_vars = [
      "ANSIBLE_SSH_ARGS='-o ForwardAgent=yes -o StrictHostKeyChecking=no -o ControlMaster=auto -o ControlPersist=60s'",
      "ANSIBLE_PIPELINING=true"
    ]
  }

  provisioner "shell" {
    inline = [
      # In case we had any temporary packages
      "sudo apt-get autoremove -y",
      # Taken from debian-server-images
      "sudo rm -fr /var/cache/ /var/lib/apt/lists/* /var/log/apt/ /etc/mailname /var/lib/cloud /var/lib/chrony /var/lib/teak-log-collector /root/* /root/.* /etc/machine-id /var/lib/dbus/machine-id",
      "sudo /bin/dash -c 'find /var/log -type f | xargs rm'",
      "sudo shred --remove /etc/ssh/ssh_host_*",
      "sudo /bin/dash -c 'if { ! -L /etc/resolve.conf ]; then rm /etc/resolve.conf; fi'",
      "sudo touch /etc/machine-id",
      # Ansible leaves behind temp directories in the home directory of the user it
      # logged in as. We always create that user with cloud-init, so nuke it and let
      # cloud-init recreate everything on boot.
      "export CURRENT_USER=`whoami`",
      "sudo userdel --remove --force $CURRENT_USER"
    ]
  }
}
