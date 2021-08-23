packer {
  required_version = "~> 1.7.3"

  required_plugins {
    amazon = {
      version = "=1.0.2-dev"
      source  = "github.com/AlexSc/amazon"
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
  default     = "packer-base-image"
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
  default     = "packer-root-image"
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
    volume_size = 2
    iops        = 3000
    throughput  = 300

    delete_on_termination = true
  }

  # Scrub our gp3 preferences from the AMI.
  ami_block_device_mappings {
    volume_type = "gp2"
    device_name = "/dev/xvda"
    volume_size = 2
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

build {
  dynamic "source" {
    for_each = local.arch_map
    iterator = arch
    labels   = ["amazon-ebs.debian"]

    content {
      name             = "debian_${arch.key}"
      ami_name         = "${var.environment}-${var.ami_prefix}-${arch.key}-${local.timestamp}"
      instance_type    = var.instance_type[arch.key]

      source_ami = local.source_ami[arch.key]
    }
  }
}
