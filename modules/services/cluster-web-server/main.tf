terraform {
  required_version = ">= 1.0.0, < 2.0.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.0.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

resource "aws_launch_configuration" "cluster-web" {
  image_id = "ami-0f2bce14c42f9427b"
  instance_type = var.instance_type
  security_groups = [aws_security_group.terraform_sg.id]
  user_data = data.template_file.user_data.rendered

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "cluster-web" {
  launch_configuration = aws_launch_configuration.cluster-web.name
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"
  min_size = var.min_size
  max_size = var.max_size

  tag {
    key = "Name"
    value = "terraform-cluster-web"
    propagate_at_launch = true
  }

}

resource "aws_security_group" "terraform_sg" {
  ingress {
    from_port = var.http_port
    to_port = var.http_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key = var.db_remote_state_key
    region = "ap-southeast-1"
   }
}

data "template_file" "user_data" {
  template = file("${path.module}/user-data.sh")
  vars = {
    server_port = var.http_port
    db_address = data.terraform_remote_state.db.outputs.db_address
    db_port = data.terraform_remote_state.db.outputs.db_port
  }
}

locals {
  http_port = 80
  any_port = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips = ["0.0.0.0/0"]
}


resource "aws_lb" "cluster-lb" {
  name = "terraform-cluster-lb"
  load_balancer_type = "application"
  subnets = data.aws_subnets.default.ids
  security_groups = [aws_security_group.alb_sg.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.cluster-lb.arn
  port = local.http_port
  protocol = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Fixed response content"
      status_code = 200
    }
  }
}

resource "aws_security_group" "alb_sg" {
  name = "${var.cluster_name}-alb"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.alb_sg.id
    from_port = local.http_port
    to_port = local.http_port
    protocol = local.tcp_protocol
    cidr_blocks = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type = "egress"
  security_group_id = aws_security_group.alb_sg.id
  from_port = local.any_port
  to_port = local.any_port
  protocol = local.any_protocol
  cidr_blocks = local.all_ips  
}


resource "aws_lb_target_group" "asg" {
  name = "terraform-asg"
  port = var.http_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id
  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100

  condition {
    path_pattern {
      values = [ "*" ]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

