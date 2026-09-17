## This represents the "before" state: a real workload running on Azure that
## we're going to migrate to AWS using AWS Application Migration Service (MGN).

resource "azurerm_resource_group" "source" {
  name     = "${var.project_name}-source-rg"
  location = var.azure_location
}

resource "azurerm_virtual_network" "source" {
  name                = "${var.project_name}-source-vnet"
  address_space       = [var.azure_vnet_cidr]
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name
}

resource "azurerm_subnet" "source" {
  name                 = "${var.project_name}-source-subnet"
  resource_group_name  = azurerm_resource_group.source.name
  virtual_network_name = azurerm_virtual_network.source.name
  address_prefixes     = [var.azure_subnet_cidr]
}

resource "azurerm_public_ip" "source_vm" {
  name                = "${var.project_name}-source-vm-ip"
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "source" {
  name                = "${var.project_name}-source-nsg"
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # MGN's replication agent needs outbound HTTPS to reach the AWS MGN
  # and S3 endpoints in the target region - default outbound rules in
  # Azure NSGs already allow this, so nothing extra is needed here.
}

resource "azurerm_network_interface" "source_vm" {
  name                = "${var.project_name}-source-nic"
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.source.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.source_vm.id
  }
}

resource "azurerm_network_interface_security_group_association" "source_vm" {
  network_interface_id     = azurerm_network_interface.source_vm.id
  network_security_group_id = azurerm_network_security_group.source.id
}

resource "azurerm_linux_virtual_machine" "source" {
  name                = "${var.project_name}-source-vm"
  location            = azurerm_resource_group.source.location
  resource_group_name = azurerm_resource_group.source.name
  size                = var.azure_vm_size
  admin_username      = var.azure_admin_username

  network_interface_ids = [azurerm_network_interface.source_vm.id]

  admin_ssh_key {
    username   = var.azure_admin_username
    public_key = file(var.azure_ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    echo "<h1>Source workload running on Azure - migrate me!</h1>" > /var/www/html/index.html
    systemctl enable nginx
    systemctl start nginx
  EOF
  )

  tags = {
    Name = "${var.project_name}-source"
    Role = "migration-source"
  }
}
