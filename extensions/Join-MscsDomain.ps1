param(
  [Parameter(Mandatory=$true)]
  [string] $DomainName,
  [Parameter(Mandatory=$true)]
  [pscredential] $Credential
)

Add-Computer -ComputerName $env:COMPUTERNAME `
    -LocalCredential $Credential `
    -DomainName $DomainName `
    -Credential $Credential `
    -Restart `
    -Force

Write-Host "Joined the Domain '$DomainName'."
Start-Sleep -Seconds 120
