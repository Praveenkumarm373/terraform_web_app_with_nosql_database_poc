//////////////////////////////////////////////////////////////////////
////
////   NETWORKS CONFIGS
////
///////////////////////////////////////////////////////////////////////

resource "azurerm_resource_group" "web_app_resource_group" {
  name     = "web-app-resource-group"
  location = "West US"
}

resource "azurerm_public_ip" "web_app_public_ip" {
  name                         = "web-app-public-ip"
  location                     = "West US"
  resource_group_name          = "${azurerm_resource_group.web_app_resource_group.name}"
  public_ip_address_allocation = "dynamic"
}

resource "azurerm_virtual_network" "web_app_virtual_network" {
  name                = "web-app-virtual-network"
  address_space       = ["10.50.0.0/16"]
  location            = "West US"
  resource_group_name = "${azurerm_resource_group.web_app_resource_group.name}"

  depends_on = ["azurerm_resource_group.web_app_resource_group"]
}

resource "azurerm_subnet" "web_zone" {
  name                 = "web-zone"
  resource_group_name  = "${azurerm_resource_group.web_app_resource_group.name}"
  virtual_network_name = "${azurerm_virtual_network.web_app_virtual_network.name}"
  address_prefix       = "10.50.1.0/24"

  depends_on = [
    "azurerm_resource_group.web_app_resource_group",
    "azurerm_virtual_network.web_app_virtual_network"
  ]
}

resource "azurerm_network_interface" "network_interface" {
  name                      = "network-interface"
  location                  = "${azurerm_resource_group.web_app_resource_group.location}"
  resource_group_name       = "${azurerm_resource_group.web_app_resource_group.name}"
  network_security_group_id = "${azurerm_network_security_group.security_group_web.id}"

  ip_configuration {
    name                          = "subnetDynamicIpConfiguration"
    subnet_id                     = "${azurerm_subnet.web_zone.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.web_app_public_ip.id}"
  }

  depends_on = [
    "azurerm_resource_group.web_app_resource_group",
    "azurerm_network_security_group.security_group_web",
    "azurerm_subnet.web_zone",
    "azurerm_public_ip.web_app_public_ip"
  ]
}

resource "azurerm_network_security_group" "security_group_web" {
  name                = "web-security-group"
  location            = "${azurerm_resource_group.web_app_resource_group.location}"
  resource_group_name = "${azurerm_resource_group.web_app_resource_group.name}"

  security_rule {
    name                       = "AllowSshAccessRule"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    source_address_prefix      = "0.0.0.0/0" # Put your ip here like so "50.25.175.23/32"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
    protocol                   = "Tcp"
  }

  security_rule {
    name                       = "AllowHttpAccessRule"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    source_address_prefix      = "0.0.0.0/0"
    source_port_range          = "*"
    destination_address_prefix = "0.0.0.0/0"
    destination_port_range     = "80"
    protocol                   = "Tcp"
  }

  security_rule {
    name                       = "AllowHttpsAccessRule"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    source_address_prefix      = "0.0.0.0/0"
    source_port_range          = "*"
    destination_address_prefix = "0.0.0.0/0"
    destination_port_range     = "443"
    protocol                   = "Tcp"
  }

  depends_on = ["azurerm_resource_group.web_app_resource_group"]
}


//////////////////////////////////////////////////////////////////////
////
////   INSTANCES CONFIGS
////
///////////////////////////////////////////////////////////////////////

//// VIRTUAL MACHINE (WEBSERVER)
resource "azurerm_virtual_machine" "web_app_virtual_machine" {
  name                  = "web-app-vm"
  location              = "West US"
  resource_group_name   = "${azurerm_resource_group.web_app_resource_group.name}"
  network_interface_ids = ["${azurerm_network_interface.network_interface.id}"]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "web-app-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "webapp"
    admin_username = "${var.web_app["admin_user"]}"
  }

  os_profile_linux_config {
    ssh_keys = [{
      path     = "/home/${var.web_app["admin_user"]}/.ssh/authorized_keys"
      key_data = "${file("../../ssh-keys/deployer-key.pub")}"
    }]
    disable_password_authentication = true
  }

  depends_on = [
    "azurerm_resource_group.web_app_resource_group",
    "azurerm_network_interface.network_interface"
  ]
}

data "azurerm_public_ip" "data_debug_public_ip" {
  name                = "${azurerm_public_ip.web_app_public_ip.name}"
  resource_group_name = "${azurerm_resource_group.web_app_resource_group.name}"

  depends_on          = ["azurerm_virtual_machine.web_app_virtual_machine"]
}

//// COSMOSDB (NoSQL DATABASE)
resource "azurerm_cosmosdb_account" "web_app_database" {
  name                = "${var.cosmos_db["name"]}"
  location            = "${azurerm_resource_group.web_app_resource_group.location}"
  resource_group_name = "${azurerm_resource_group.web_app_resource_group.name}"
  offer_type          = "Standard"
  kind                = "MongoDB"
  ip_range_filter     = "${data.azurerm_public_ip.data_debug_public_ip.ip_address}/32"

  consistency_policy {
    consistency_level = "BoundedStaleness"
  }

  failover_policy {
    location = "West US"
    priority = 0
  }

  depends_on = ["azurerm_resource_group.web_app_resource_group"]
}

resource "null_resource" "ansible_provisioner" {
  triggers {
    always = "${uuid()}"
  }

  provisioner "local-exec" {
    command = "sleep 20; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ${var.web_app["admin_user"]} --private-key ../../ssh-keys/deployer-key -i '${data.azurerm_public_ip.data_debug_public_ip.ip_address},' -e 'provider=azure database_user=${var.cosmos_db["name"]} database_password=${azurerm_cosmosdb_account.web_app_database.primary_master_key}' ../../ansible/web_server.deploy.yml"
  }

  depends_on = ["data.azurerm_public_ip.data_debug_public_ip"]
}


//////////////////////////////////////////////////////////////////////
////
////   DEBUG CONFIGS
////
///////////////////////////////////////////////////////////////////////

output "web_server_ip" {
  value = "Application running at: ${data.azurerm_public_ip.data_debug_public_ip.ip_address}"
}
