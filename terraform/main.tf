# Copyright 2022 Teak.io, Inc.
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

terraform {
  backend "s3" {
    bucket         = "teak-terraform-state"
    key            = "base_image_factory"
    region         = "us-east-1"
    dynamodb_table = "teak-terraform-locks"
    encrypt        = true
    kms_key_id     = "a285ccc4-035b-4436-834f-7e0b2d5b0f60"
  }

  required_version = ">= 1.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4"
    }
  }
}

provider "aws" {
  region = var.region
  alias  = "meta_read"
}

module "ci_cd_account" {
  source  = "GoCarrot/accountomat_read/aws"
  version = "0.0.3"

  providers = {
    aws = aws.meta_read
  }

  canonical_slug = terraform.workspace
}

locals {
  service = "BaseImageFactory"

  default_tags = {
    Managed     = "terraform"
    Environment = module.ci_cd_account.environment
    CostCenter  = local.service
    Application = local.service
    Service     = local.service
  }
}

provider "aws" {
  region = var.region
  alias  = "admin"

  default_tags {
    tags = local.default_tags
  }
}

module "build-trigger" {
  providers = {
    aws = aws.admin
  }

  source = "GoCarrot/declare-ami-dependency/aws"

  branch                 = var.branch
  build_from_account     = terraform.workspace
  circleci_project_slug  = var.circleci_project_slug
  source_ami_name_prefix = var.source_ami_name_prefix
}
