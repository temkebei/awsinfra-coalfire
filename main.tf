locals {
  # Ids for multiple sets of EC2 instances, merged together
  env = "Dev"
}

provider "aws" {
    region = "us-east-1"
}
module "vpc" {
  source = "git@github.com:temkebei/awsvpc.git"
  environment = local.env
  vpc_cidr = "10.1.0.0/16"
  public_subnets_cidr  = ["10.1.0.0/24","10.1.1.0/24"]
  private_subnets_cidr = ["10.1.2.0/24","10.1.3.0/24"]
  availability_zones = ["us-east-1a","us-east-1b","us-east-1c"]
}

module "sg-ec2" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "${local.env}-EC2-SG"
  description = "${local.env}-EC2-SG"
  vpc_id      = module.vpc.vpc_id
  ingress_cidr_blocks      = ["0.0.0.0/0"]
  ingress_rules            = ["ssh-tcp","http-80-tcp"]
  egress_cidr_blocks      = ["0.0.0.0/0"]
  egress_rules            = ["all-all"]
}

module "sg-lb" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "${local.env}-LB-SG"
  description = "${local.env}-LB-SG"
  vpc_id      = module.vpc.vpc_id
  ingress_cidr_blocks      = ["0.0.0.0/0"]
  ingress_rules            = ["http-80-tcp"]
  egress_cidr_blocks      = ["0.0.0.0/0"]
  egress_rules            = ["all-all"]
}

module "ec2" {
  source = "git@github.com:temkebei/awsec2.git"
  ami = "ami-0b0af3577fe5e3532"
  instance_type = "t2.micro"
  key_name = "Kebei"
  vpc_security_group_ids = [module.sg-ec2.security_group_id]
  subnet_id = module.vpc.public_subnets_id[1]
  root_block_device = [{
      volume_size = 20
  }]
  tags = {
      Name = local.env
    }
  
}

module "asg" {
  source = "git@github.com:temkebei/awsasg.git"
  name = "${local.env}-asg"
  ami = "ami-0b0af3577fe5e3532"
  instance_type = "t2.micro"
  security_group_ids = [module.sg-ec2.security_group_id]
  desired_capacity = 2
  max_size = 6
  min_size = 2
  subnet_id = [module.vpc.private_subnets_id[0]]
  target_group_arns = [module.alb.tg_arn[0]]
}

module "s3" {
    source = "git@github.com:temkebei/awss3.git"
    bucket = "kebei-coalfire"
    region = "us-east-1"
    lifecycle_rule = [{
        id                                     = "Move to glacier"
        enabled                                = true
        prefix                                 = "Images/"
        tags                                   = {}
        transition = [
           {
               days = 90
               storage_class = "DEEP_ARCHIVE"
           }
        ]
       
    },
    
    {
        id                                     = "Delete permanently"
        enabled                                = true
        prefix                                 = "Logs/"
        tags                                   = {}
        expiration = {
              days = 90
              expired_object_delete_marker = false
        }
       
    }
    ]
}


module "alb" {
  source = "git@github.com:temkebei/awsalb.git"
  lb_subnet = [module.vpc.public_subnets_id[0],module.vpc.public_subnets_id[1]]
  lb_SG = [module.sg-lb.security_group_id]
  name = "${local.env}-webapp"
  tg_vpc_id = module.vpc.vpc_id
  target_groups = [
    {
      name      = "${local.env}-Web-TG-80"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    }
    ]
  listener_port = 80
  listener_porotocol = "HTTP"
  
}