# Copyright 2021 Teak.io, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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

variable "build_account_canonical_slug" {
  type        = string
  description = "The canonical_slug for an account as assigned by accountomat to build the AMI in."
}

variable "cost_center" {
  type        = string
  default     = "packer"
  description = "Value to be assigned to the CostCenter tag on all temporary resources and created AMIs"
}

variable "application" {
  type        = string
  default     = "None"
  description = "Value to be assigned to the Application tag on created AMIs"
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

variable "commit_id" {
  type        = string
  description = "The full git sha of the commit that the image is being built from."
  default     = env("CIRCLE_SHA1")
}

variable "use_generated_security_group" {
  type        = bool
  description = "If false, will use the security group configured for the account. If true, will have packer generate a new security group for this build."
  default     = false
}

data "amazon-parameterstore" "account_info" {
  region = var.region

  name = "/omat/account_registry/${var.build_account_canonical_slug}"
}

data "amazon-parameterstore" "role_arn" {
  region = var.region

  name = "${jsondecode(data.amazon-parameterstore.account_info.value)["prefix"]}/roles/packer"
}

data "amazon-parameterstore" "security_group_name" {
  region = var.region

  name = "${jsondecode(data.amazon-parameterstore.account_info.value)["prefix"]}/config/ServerImages/security_group_name"
}

data "amazon-parameterstore" "instance_profile" {
  region = var.region

  name = "${jsondecode(data.amazon-parameterstore.account_info.value)["prefix"]}/config/ServerImages/instance_profile"
}

data "amazon-parameterstore" "ami_users" {
  region = var.region

  name = "${jsondecode(data.amazon-parameterstore.account_info.value)["prefix"]}/config/ServerImages/ami_consumers"
}

# Pull the latest root image
data "amazon-ami" "base_x86_64_debian_ami" {
  assume_role {
    role_arn = data.amazon-parameterstore.role_arn.value
  }

  filters = {
    virtualization-type = "hvm"
    name                = "${jsondecode(data.amazon-parameterstore.account_info.value)["environment"]}_${var.source_ami_name_prefix}*"
    architecture        = "x86_64"
    state               = "available"
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
    name                = "${jsondecode(data.amazon-parameterstore.account_info.value)["environment"]}_${var.source_ami_name_prefix}*"
    architecture        = "arm64"
    state               = "available"
  }
  region      = var.region
  owners      = var.source_ami_owners
  most_recent = true
}

locals {
  account_info        = jsondecode(data.amazon-parameterstore.account_info.value)
  security_group_name = var.use_generated_security_group ? "" : data.amazon-parameterstore.security_group_name.value
  environment         = local.account_info["environment"]

  timestamp = regex_replace(timestamp(), "[- :]", "")
  source_ami = {
    x86_64 = data.amazon-ami.base_x86_64_debian_ami
    arm64  = data.amazon-ami.base_arm64_debian_ami
  }
  role_arn = data.amazon-parameterstore.role_arn.value
  arch_map = { x86_64 = "amd64", arm64 = "arm64" }

  commit_id = coalesce(var.commit_id, "in-dev")
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

  dynamic "security_group_filter" {
    for_each = [for s in [local.security_group_name] : s if s != ""]

    content {
      filters = {
        "group-name" = local.security_group_name
      }
    }
  }

  run_volume_tags = {
    Managed     = "packer"
    Environment = local.environment
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
      ami_name      = "${local.environment}_${var.ami_prefix}_${arch.key}.${local.timestamp}"
      instance_type = var.instance_type[arch.key]

      source_ami = local.source_ami[arch.key].id

      run_tags = {
        Application = "ImageFactory"
        Environment = local.environment
        CostCenter  = var.cost_center
        Managed     = "packer"
        Service     = "${local.environment}_${var.ami_prefix}_${arch.key}.${local.timestamp}"
      }

      tags = {
        Application = var.application
        Environment = local.environment
        CostCenter  = var.cost_center
        SourceAmi   = local.source_ami[arch.key].name
        SourceAmiId = local.source_ami[arch.key].id
        BuildCommit = local.commit_id
      }

      user_data = <<-EOT
      #cloud-config
      write_files:
        - content: |
            [Service]
            Environment="TEAK_SERVICE=${local.environment}_${var.ami_prefix}_${arch.key}.${local.timestamp}"
          path: /run/systemd/system/teak-.service.d/01_build_environment.conf
          owner: root:root
          permissions: '0644'
EOT
    }
  }

  source "vagrant.debian" {

  }

  provisioner "ansible" {
    playbook_file = "${path.root}/${var.ansible_playbook}"
    extra_arguments = [
      "--extra-vars", "build_environment=${local.environment} region=${var.region} build_type=${source.type}"
    ]
    ansible_env_vars = [
      "ANSIBLE_SSH_ARGS='-o ForwardAgent=yes -o StrictHostKeyChecking=no -o ControlMaster=auto -o ControlPersist=60s'",
      "ANSIBLE_PIPELINING=true"
    ]

    use_proxy = false
  }

  # Remove any temporary build-dep style packages and generate a package manifest.
  provisioner "shell" {
    inline = [
      # In case we had any temporary packages
      "sudo apt-get autoremove --purge -y -o 'APT::AutoRemove::SuggestsImportant=false' -o 'APT::AutoRemove::RecommendsImportant=false'",
      "sudo dpkg-query --show > /tmp/package_manifest.txt",
      "sudo dpkg-query --show -f '$${source:Package}\\t$${source:Version}\\n' | sort | uniq > /tmp/source_package_manifest.txt"
    ]
  }

  # Download the package manifest locally.
  provisioner "file" {
    source      = "/tmp/package_manifest.txt"
    destination = "${path.root}/manifests/${source.name}.txt"
    direction   = "download"
  }

  provisioner "file" {
    source      = "/tmp/source_package_manifest.txt"
    destination = "${path.root}/manifests/source_${source.name}.txt"
    direction   = "download"
  }

  # Clean up the server so we can pretend it's never been booted before.
  provisioner "shell" {
    inline = [
      # Go ahead and nuke our mainfest
      "sudo rm -fr /tmp/package_manifest.txt",
      "sudo rm -fr /tmp/source_package_manifest.txt",
      # Taken from debian-server-images
      "sudo rm -fr /var/cache/ /var/lib/apt/lists/* /var/log/apt/ /etc/mailname /var/lib/cloud /var/lib/chrony /var/lib/teak-log-collector /root/.bash_history /root/.ssh/ /root/.ansible/ /root/.bundle/ /etc/machine-id /var/lib/dbus/machine-id",
      # Ensure we stop things that'll log before we clear logs
      "sudo systemctl stop teak-log-collector.service teak-configurator.service systemd-journald.service systemd-journald-dev-log.socket systemd-journald.socket systemd-journald-audit.socket",
      "sudo /bin/dash -c 'find /var/log -type f -not -empty | tee /dev/stderr | xargs rm'",
      # I also want to clear the empty log folder.
      "sudo rm -fr /var/log/journal/*",
      "sudo shred --remove /etc/ssh/ssh_host_*",
      "sudo /bin/dash -c 'if [ ! -L /etc/resolv.conf ]; then rm /etc/resolv.conf; fi'",
      "sudo touch /etc/machine-id",
      # Ansible leaves behind temp directories in the home directory of the user it
      # logged in as. We always create that user with cloud-init, so nuke it and let
      # cloud-init recreate everything on boot.
      "export CURRENT_USER=`whoami`",
      "sudo userdel --remove --force $CURRENT_USER"
    ]
  }

  post-processor "manifest" {
    output      = "${path.root}/manifests/packer-manifest.json"
    custom_data = {
      arch = "${trimprefix(source.name, "debian_")}"
    }
  }
}
