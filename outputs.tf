output "azure_source_vm_public_ip" {
  value = azurerm_public_ip.source_vm.ip_address
}

output "azure_source_vm_private_ip" {
  value = azurerm_network_interface.source_vm.private_ip_address
}

output "aws_target_vpc_id" {
  value = aws_vpc.target.id
}

output "aws_staging_subnet_id" {
  value = aws_subnet.staging.id
}

output "aws_target_subnet_id" {
  value = aws_subnet.target.id
}

output "aws_mgn_staging_sg_id" {
  value = aws_security_group.mgn_staging.id
}

output "aws_cutover_sg_id" {
  value = aws_security_group.cutover.id
}
