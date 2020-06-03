using namespace System.Net
param($Request, $TriggerMetadata)
############### Settings ##############
#Only used if Autodetection fails, e.g. multiple DNS zones, etc.
$ResourceGroup = "AzDynDNS"
$ZoneName = "Limenetworks.it"
############### /Settings ##############
if (!$request.headers.authorization) {
    write-host "No API key"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = "401 - No API token or token is invalid."
        })
    exit
}

$Base64APIKey = $request.headers.authorization -split " " | select-object -last 1
$APIKey = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($Base64APIKey)) -split ":" | select-object -last 1

if ($APIKey -ne $env:APIKey) {
    write-host "Invalid API key"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = "401 - No API token or token is invalid."
        })
    exit
}

$AutoDetect = (get-azresource -ResourceType "Microsoft.Network/dnszones")
If ($AutoDetect) { 
    write-host "Using Autodetect."
    $ZoneName = $Autodetect.name
    $ResourceGroup = $AutoDetect.ResourceGroupName
}


$Domain = $request.Query.hostname.split('.') | select-object -first 1
$NewIP = $request.Query.myip
write-host "$domain has $newip. Checking record and creating if required."
$ExistingRecord = Get-AzDnsRecordSet -ResourceGroupName $ResourceGroup -ZoneName $ZoneName -Name $Domain -RecordType A -ErrorAction SilentlyContinue
if (!$ExistingRecord) {
    write-host "Creating new record for $domain"
    New-AzDnsRecordSet -name $domain -Zonename $ZoneName -ResourceGroupName $ResourceGroup -RecordType A -Ttl 60 -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $NewIP)
    Push-OutputBinding -Name Response -Value (  [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = "good $newip"
        })
    exit 
}
else {
    if ($ExistingRecord.Records[-1].Ipv4Address -ne $NewIP) { 
        write-host "Updating record for $domain - new IP is $newIP"
        $ExistingRecord.Records[-1].Ipv4Address = $NewIP
        Set-AzDnsRecordSet -RecordSet $ExistingRecord
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = "good $newip"
            })
    }
    else {
        write-host "No Change - $domain IP is still $newIP"
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = "nochg $NewIP"
            })
    }
    exit
}
