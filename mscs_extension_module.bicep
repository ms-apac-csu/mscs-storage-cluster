// ************************************************************************************************
// * Parameters
// ************************************************************************************************
@description('Admin Username for the Virtual Machine.')
param admin_name string

@description('Admin Password for the Virtual Machine.')
@maxLength(18)
@secure()
param admin_password string

param location string
param domain_name string
param domain_netbios_name string
param domain_server_ip string = '172.16.0.100'
param vm_01_name string = 'mscswvm-01'
param vm_02_name string = 'mscswvm-02'
param vm_03_name string = 'mscswvm-03'

resource vm_01_resource 'Microsoft.Compute/virtualMachines@2022-11-01' existing = {
  name: vm_01_name
 }

 resource vm_02_resource 'Microsoft.Compute/virtualMachines@2022-11-01' existing = {
  name: vm_02_name
 }

 resource vm_03_resource 'Microsoft.Compute/virtualMachines@2022-11-01' existing = {
  name: vm_03_name
 }
 
resource vm_01_cse 'Microsoft.Compute/VirtualMachines/extensions@2022-11-01' = {
  parent: vm_01_resource
  name: 'cse_dc_extension'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.9'
    settings: {
      fileUris: ['https://raw.githubusercontent.com/ms-apac-csu/mscs-storage-cluster/main/dsc-configurations/Install-VmFeatures.ps1']
    }
    protectedSettings: {
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File Install-VmFeatures.ps1 -VmRole domain -AdminName ${admin_name} -AdminPassword ${admin_password} -DomainName ${domain_name} -DomainNetBiosName ${domain_netbios_name} -DomainServerIpAddress ${domain_server_ip}'
    }
  }
}

resource vm_02_cse 'Microsoft.Compute/VirtualMachines/extensions@2022-11-01' = {
  parent: vm_02_resource
  name: 'cse_fs_extension'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.9'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: ['https://raw.githubusercontent.com/ms-apac-csu/mscs-storage-cluster/main/dsc-configurations/Install-VmFeatures.ps1']
    }
    protectedSettings: {
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File Install-VmFeatures.ps1 -VmRole failover -AdminName ${admin_name} -AdminPassword ${admin_password} -DomainName ${domain_name} -DomainNetBiosName ${domain_netbios_name} -DomainServerIpAddress ${domain_server_ip}'
    }
  }
}

resource vm_03_cse 'Microsoft.Compute/VirtualMachines/extensions@2022-11-01' = {
  parent: vm_03_resource
  name: 'cse_fs_extension'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.9'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: ['https://raw.githubusercontent.com/ms-apac-csu/mscs-storage-cluster/main/dsc-configurations/Install-VmFeatures.ps1']
    }
    protectedSettings: {
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File Install-VmFeatures.ps1 -VmRole failover -AdminName ${admin_name} -AdminPassword ${admin_password} -DomainName ${domain_name} -DomainNetBiosName ${domain_netbios_name} -DomainServerIpAddress ${domain_server_ip}'
    }
  }
}
