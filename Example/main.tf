provider "aws" {
  region = local.region
}

locals {
  region = var.region
  name   = "efs-ex-${replace(basename(path.cwd), "_", "-")}"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Name = local.name


  }
}

data "aws_availability_zones" "available" {}   

data "aws_caller_identity" "current" {}



################################################################################
# EFS Module
################################################################################

module "efs" {
  source = "../../../Modules/efs"

  # File system
  name           = local.name
  creation_token = local.name
  encrypted      = true
  kms_key_arn    = module.kms.key_arn

  performance_mode                = var.performance_mode
  throughput_mode                 = var.throughput_mode
  provisioned_throughput_in_mibps = var.provisioned_throughput_in_mibps

  #   lifecycle_policy = {
  #     transition_to_ia                    = "AFTER_30_DAYS"
  #     transition_to_primary_storage_class = "AFTER_1_ACCESS"
  #   }

  lifecycle_policy = var.lifecycle_policy

  # File system policy
  attach_policy                      = var.attach_policy
  bypass_policy_lockout_safety_check = var.bypass_policy_lockout_safety_check
  policy_statements = [
    {
      sid     = "Example"
      actions = ["elasticfilesystem:ClientMount"]
      principals = [
        {
          type        = "AWS"
          identifiers = [data.aws_caller_identity.current.arn]
        }
      ]
    }
  ]

  # Mount targets / security group
  mount_targets              = { for k, v in zipmap(local.azs, var.private_subnets) : k => { subnet_id = v } }
  security_group_description = "Example EFS security group"
  security_group_vpc_id      = var.vpc_id
  security_group_rules = {
    vpc = {
      # relying on the defaults provdied for EFS/NFS (2049/TCP + ingress)
      description = "NFS ingress from VPC private subnets"
      cidr_blocks = var.private_subnets_cidr_blocks
    }
  }

  # Access point(s)
  access_points = {
    posix_example = {
      name = "posix-example"
      posix_user = {
        gid            = 1001
        uid            = 1001
        secondary_gids = [1002]
      }

      tags = {
        Additionl = "yes"
      }
    }
    root_example = {
      root_directory = {
        path = "/example"
        creation_info = {
          owner_gid   = 1001
          owner_uid   = 1001
          permissions = "755"
        }
      }
    }
  }

  # Backup policy
  enable_backup_policy = var.enable_backup_policy

  # Replication configuration
  create_replication_configuration = var.create_replication_configuration
  replication_configuration_destination = {
    region = var.region
  }

  tags = local.tags
}

# module "efs_default" {
#   source = "../.."

#   name = "${local.name}-default"

#   tags = local.tags
# }

# module "efs_disabled" {
#   source = "../.."

#   create = false
# }

################################################################################
# Supporting Resources
################################################################################

# module "vpc" {
#   source  = "terraform-aws-modules/vpc/aws"
#   version = "~> 3.0"

#   name = local.name
#   cidr = "10.99.0.0/18"

#   azs             = local.azs
#   public_subnets  = ["10.99.0.0/24", "10.99.1.0/24", "10.99.2.0/24"]
#   private_subnets = ["10.99.3.0/24", "10.99.4.0/24", "10.99.5.0/24"]

#   enable_nat_gateway      = false
#   single_nat_gateway      = true
#   map_public_ip_on_launch = false

#   tags = local.tags
# }

module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 1.0"

  aliases               = ["efs/${local.name}"]
  description           = "EFS customer managed key"
  enable_default_policy = true

  # For example use only
  deletion_window_in_days = 7

  tags = local.tags
}
