$setup = Join-Path $InstallerFolder 'setup.exe'
if (-not (Test-Path $setup)) {
    throw "setup.exe not found in $InstallerFolder"
}

$ctrPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
$ctr = Get-ItemProperty $ctrPath -ErrorAction Stop

# ProductReleaseIds can contain multiple entries, for example Office + Visio/Project.
# Prefer the main Microsoft 365 Apps product for the XML Product ID.
$productIds = @()
if ($ctr.ProductReleaseIds) {
    $productIds = ($ctr.ProductReleaseIds -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

$preferredOrder = @(
    'O365ProPlusEEANoTeamsRetail',
    'O365ProPlusRetail',
    'O365BusinessEEANoTeamsRetail',
    'O365BusinessRetail'
)

$productId = $null
foreach ($preferred in $preferredOrder) {
    if ($productIds -contains $preferred) {
        $productId = $preferred
        break
    }
}

if (-not $productId) {
    throw "Could not determine a supported Microsoft 365 Apps product ID from ProductReleaseIds: $($ctr.ProductReleaseIds)"
}

# Determine bitness
$officeClientEdition = if ([string]$ctr.Platform -match 'x64|64') { '64' } else { '32' }

# Preserve existing excluded apps if the ClickToRun config exposes them.
# This is observed in the field as values like O365ProPlusRetail.ExcludedApps.
# If nothing is present, we just exclude Lync.
$existingExcludedApps = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($prop in $ctr.PSObject.Properties) {
    if ($prop.Name -like '*.ExcludedApps' -and $prop.Value) {
        foreach ($app in ([string]$prop.Value -split '[,;]')) {
            $name = $app.Trim()
            if ($name) {
                [void]$existingExcludedApps.Add($name)
            }
        }
    }
}

# Always exclude Skype for Business
[void]$existingExcludedApps.Add('Lync')

# Build XML ExcludeApp nodes
$excludeNodes = ($existingExcludedApps | Sort-Object | ForEach-Object {
    "      <ExcludeApp ID=""$_"" />"
}) -join [Environment]::NewLine

$xml = @"
<Configuration>
  <Add OfficeClientEdition="$officeClientEdition" Version="MatchInstalled">
    <Product ID="$productId">
      <Language ID="MatchInstalled" />
$excludeNodes
    </Product>
  </Add>
  <Display Level="Full" AcceptEULA="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
</Configuration>
"@

$xmlPath = Join-Path $env:TEMP 'remove-skype-dynamic.xml'
$xml | Set-Content -Path $xmlPath -Encoding UTF8

Write-Host "Using Product ID: $productId"
Write-Host "Using OfficeClientEdition: $officeClientEdition"
Write-Host "Excluded apps: $(([string[]]$existingExcludedApps | Sort-Object) -join ', ')"
Write-Host "XML path: $xmlPath"

$proc = Start-Process -FilePath $setup -ArgumentList "/configure `"$xmlPath`"" -Wait -PassThru -WindowStyle Hidden

if ($proc.ExitCode -ne 0) {
    throw "ODT failed with exit code $($proc.ExitCode)"
}

Write-Host "ODT finished successfully."
