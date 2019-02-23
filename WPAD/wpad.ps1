## wpad.ps1

Param(
    [Parameter(Mandatory=$true)]
    [string]$ClientIP,
    [Parameter(Mandatory=$true)]
    [string]$ScriptDir
)

Function Get-AdSiteAndSubnetFromIP {
<#
.Synopsis
Get the matching AD Site and Subnet for a given IP Address
.DESCRIPTION
Get the matching AD Site and Subnet for a given IP Address.  The results will be returned as a Hash.
https://superuser.com/questions/758372/query-site-for-given-ip-from-ad-sites-and-services

.EXAMPLE
Get-AdSiteAndSubnetFromIP -ip 172.28.68.53

ADSite        ADSubnet     
------        --------     
SiteA         10.1.0.0/16
.EXAMPLE

(Get-AdSiteAndSubnetFromIP -ip 172.28.68.53).ADSite

SiteA
#>
    param([string]$ip
        )
    $site = nltest /DSADDRESSTOSITE:$ip /dsgetsite 2>$null
    if ($LASTEXITCODE -eq 0) {
        $split = $site[3] -split "\s+"
        # validate result is for an IPv4 address before continuing
        if ($split[1] -match [regex]"^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$") {
            "" | Select-Object @{l="ADSite";e={$split[2]}}, @{l="ADSubnet";e={$split[3]}}
        }
    }
}

Set-Location $ScriptDir

#$ClientIP = "10.1.2.3"

$ADSite = (Get-AdSiteAndSubnetFromIP -ip $ClientIP).ADSite
#Lower case site name for consistence in generated JavaScript
$ADSiteL = ($ADSite -replace "-", "_").ToLower()

$FileList =@()
$FileList += Get-ChildItem .\wpad.d\*.txt
if (Test-Path ".\custom.d\*.txt") { 
    $FileList += Get-ChildItem .\custom.d\*.txt
}
if (Test-Path ".\$ADSite.d\*.txt") { 
    $FileList += Get-ChildItem .\$ADSite.d\*.txt
}



$Content = ""

foreach ($filename in ($FileList | Select-Object Name, @{L="Path";E={".\" +$_.Directory.Name + "\" + $_.name }}| Sort-Object Name | Select-Object Path | ForEach-Object {$_.Path })) {

   $Content += "/* START FILE: " + $filename + " */`n`n"
   $Content += Get-Content -Path $filename -Raw 
   $Content += "`n/* END FILE: " + $filename + " */`n`n"

}

$Content = $Content.Replace("%SITE%",$ADSite)
$Content = $Content.Replace("%WEBSERVER%",$env:COMPUTERNAME)
$Content = $Content.Replace("%GENERATED%",(Get-Date).ToShortDateString() + " " + (Get-Date).ToLongTimeString() )
$Content = $Content.Replace("%SITE%",$ADSite)
$Content = $Content.Replace("%SITEL%",$ADSiteL)

$Content


