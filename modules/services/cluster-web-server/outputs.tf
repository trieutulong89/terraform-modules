output "lb_dns" {
  description = "The domain name of LB"
  value = aws_lb.cluster-lb.dns_name
}

output "asg_name" {
  value = aws_autoscaling_group.cluster-web.name
  description = "The name of the Auto Scaling Group"
}

output "alb_security_group_id" {
  value = aws_security_group.alb_sg.id
  description = "The ID of the Security group attached to the load balancer"
}