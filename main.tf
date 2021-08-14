provider "aws" {
    region = "us-east-1"
}
module "vpc" {
  source = "git@github.com:temkebei/awsvpc.git"
  environment = "prod"
  vpc_cidr = "10.1.0.0/16"
  public_subnets_cidr  = ["10.1.0.0/24","10.1.1.0/24"]
  private_subnets_cidr = ["10.1.2.0/24","10.1.3.0/24"]
  availability_zones = ["us-east-1a","us-east-1b","us-east-1c"]
}

module "sg-ec2" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "EC2-SG"
  description = "EC2-SG"
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
  subnet_id = module.vpc.public_subnets_id[0]
  tags = {
      Name = "test"
    }
  
}

module "asg" {
  source = "git@github.com:temkebei/awsasg.git"
  name = "asg"
  ami = "ami-0b0af3577fe5e3532"
  instance_type = "t2.micro"
  security_group_ids = [module.sg-ec2.security_group_id]
  desired_capacity = 1
  max_size = 1
  min_size = 1
  subnet_id = [module.vpc.public_subnets_id[0]]
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
               days = 20
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
  lb_SG = [module.sg-ec2.security_group_id]
  name = "webapp"
  tg_vpc_id = module.vpc.vpc_id
  target_groups = [
    {
      name      = "Web-TG-80"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    }
    ]
  listener_port = 80
  listener_porotocol = "HTTP"
  
}