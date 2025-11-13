# Output the connection details
output "control_plane_ip" {
  value = aws_instance.control_plane.public_ip
}

output "worker_node_ip" {
  value = aws_instance.worker_node.*.public_ip
}

output "ssh_connection_command_control_plane" {
  value = "ssh -i k8s-lab-key.pem ubuntu@${aws_instance.control_plane.public_ip}"
}