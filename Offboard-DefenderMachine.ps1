<#
.SYNOPSIS
    Offboards a machine from Microsoft Defender for Endpoint using the
    "Offboard machine" API.

.DESCRIPTION
    The script interactively prompts for ClientID, ClientSecret, TenantID and
    MachineID, obtains an OAuth2 token (client credentials flow) from Entra ID,
    and sends the offboarding request to the Microsoft Defender for Endpoint API.

    NOTE: Offboarding of Linux servers through this API is generally available
    (GA) as of August 2026 and requires the MDE agent on Linux version
    101.26062.0007 or later. The API also supports Windows and macOS.
    See README.md for details.

    Reference:
    https://learn.microsoft.com/en-us/defender-endpoint/api/offboard-machine-api

.NOTES
    Author : Guido Imperatore
    License: MIT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$MachineId,

    [Parameter(Mandatory = $false)]
    [string]$Comment = "Offboard machine by automation"
)

# --- Minimum requirements ---------------------------------------------------
#Requires -Version 5.1

function Read-RequiredValue {
    param(
        [string]$Prompt,
        [string]$CurrentValue
    )
    while ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        $CurrentValue = Read-Host -Prompt $Prompt
    }
    return $CurrentValue.Trim()
}

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Microsoft Defender for Endpoint - Offboard Machine" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# --- Interactive parameter collection ---------------------------------------
$ClientId  = Read-RequiredValue -Prompt "Enter the ClientID (Application ID)"           -CurrentValue $ClientId
$TenantId  = Read-RequiredValue -Prompt "Enter the TenantID (Directory ID)"             -CurrentValue $TenantId
$MachineId = Read-RequiredValue -Prompt "Enter the MachineID (40 hex characters)"       -CurrentValue $MachineId

# The secret is requested securely (masked input)
$SecureSecret = Read-Host -Prompt "Enter the ClientSecret" -AsSecureString
$BSTR         = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureSecret)
$ClientSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
    Write-Host "[ERROR] The ClientSecret cannot be empty." -ForegroundColor Red
    exit 1
}

# Optional: comment associated with the action (required by the API)
$inputComment = Read-Host -Prompt "Comment to associate with the action [default: '$Comment']"
if (-not [string]::IsNullOrWhiteSpace($inputComment)) {
    $Comment = $inputComment.Trim()
}

Write-Host ""
Write-Host "[1/2] Requesting access token from Entra ID..." -ForegroundColor Yellow

# --- Obtain OAuth2 token (client credentials) -------------------------------
# Audience/Resource of the Defender for Endpoint API
$Resource   = "https://api.securitycenter.microsoft.com"
$TokenUri   = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

$TokenBody = @{
    client_id     = $ClientId
    scope         = "$Resource/.default"
    client_secret = $ClientSecret
    grant_type    = "client_credentials"
}

try {
    $TokenResponse = Invoke-RestMethod -Method Post -Uri $TokenUri `
        -ContentType "application/x-www-form-urlencoded" -Body $TokenBody -ErrorAction Stop
    $AccessToken = $TokenResponse.access_token
}
catch {
    Write-Host "[ERROR] Unable to obtain the access token." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message -ForegroundColor Red }
    exit 1
}

if ([string]::IsNullOrWhiteSpace($AccessToken)) {
    Write-Host "[ERROR] Token not received. Check ClientID, Secret and TenantID." -ForegroundColor Red
    exit 1
}

Write-Host "      Token obtained successfully." -ForegroundColor Green
Write-Host ""
Write-Host "[2/2] Sending offboarding request for machine '$MachineId'..." -ForegroundColor Yellow

# --- Call the offboarding API -----------------------------------------------
$OffboardUri = "https://api.security.microsoft.com/api/machines/$MachineId/offboard"

$Headers = @{
    "Authorization" = "Bearer $AccessToken"
    "Content-Type"  = "application/json"
}

$RequestBody = @{
    Comment = $Comment
} | ConvertTo-Json

try {
    $Response = Invoke-RestMethod -Method Post -Uri $OffboardUri `
        -Headers $Headers -Body $RequestBody -ErrorAction Stop

    Write-Host ""
    Write-Host "[OK] Offboarding request accepted." -ForegroundColor Green
    Write-Host "--------------------------------------------------------------" -ForegroundColor DarkGray
    $Response | Format-List
    Write-Host "--------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "NOTE: you can monitor the action status in the Defender portal" -ForegroundColor Cyan
    Write-Host "      or through the 'Get MachineAction' API." -ForegroundColor Cyan
}
catch {
    Write-Host ""
    Write-Host "[ERROR] The offboarding request failed." -ForegroundColor Red
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
        Write-Host "HTTP status code: $statusCode" -ForegroundColor Red
    }
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message -ForegroundColor Red }

    Write-Host ""
    Write-Host "Reminder: for Linux devices the MDE agent must be at version" -ForegroundColor Yellow
    Write-Host "101.26062.0007 or later for this API to be supported." -ForegroundColor Yellow
    exit 1
}
finally {
    # Clean up the variable holding the plain-text secret
    $ClientSecret = $null
    [System.GC]::Collect()
}
