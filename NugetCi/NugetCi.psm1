
function Get-SteppedNugetVersion
{
    Param(
        [Parameter(Mandatory=$True, Position=0)]
        [String]$Version,
        [String]$Patch
    )
    
    $Parts = $Version.split('.')
    if (![String]::IsNullOrEmpty($Patch)) {
        $Parts[2] = $Patch
    }
    else {
        $Parts[2]++
    }
    
    return [String]::Join(".", $Parts)
}

function Get-NugetCiLatestPackageVersion
{
    Param (
        [Parameter(Mandatory=$True, Position=0)]
        [String]$UrlBase,
        [Parameter(Mandatory=$True, Position=1)]
        [String]$NuGetPackageId,
        [Parameter(Mandatory=$False, Position=2)]
        [PSCredential]$Credential
    )
    
    $FeedUrl   = "https://$UrlBase/nuget/v2/Packages()?`$filter=Id%20eq%20'$nuGetPackageId'"
    $WebClient = New-Object System.Net.WebClient
    
    if ($Null -ne $Credential) {
        $Basic = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Credential.GetNetworkCredential().UserName):$($Credential.GetNetworkCredential().Password)"));
        $webClient.Headers["Authorization"] = "Basic $basic"
    }
    
    $QueryResults = [xml]($WebClient.DownloadString($FeedUrl))
    $Version      = $QueryResults.feed.entry | ForEach-Object { $_.Properties.Version } | Select-Object -First 1
    
    if (!$Version) {
        $Version = "0.0.0.0"
    }
    
    return $Version
}

function Invoke-NugetCiVersionStepper
{
    Param (
        [Parameter(Mandatory=$True, Position=0)]
        [String]$BasePath,
        [Parameter(Mandatory=$True, Position=1)]
        [String]$UrlBase,
        [Parameter(Mandatory=$True, Position=2)]
        [String]$NuGetPackageId,
        [Parameter(Mandatory=$False, Position=3)]
        [PSCredential]$Credential,
        [Parameter(Mandatory=$False, Position=4)]
        [String]$Patch
    )

    $BasePath   = Resolve-Path $BasePath
    $PackageIds = (Get-ChildItem $BasePath -Recurse -Include '*.nuspec').FullName | % { Split-Path (Split-Path $_ -Parent) -Leaf }

    $PackageIds | ForEach-Object {
        $LastVersion  = Get-NugetCiLatestPackageVersion $UrlBase $_ $Credential
        $Version      = Get-SteppedNugetVersion $LastVersion $Patch
        $VariableName = ($_ + "Version")
        $Package      = Get-ChildItem $BasePath -Include "$($_).nuspec" -Recurse

        $Package | ForEach-Object { 
            $Path       = $_
            $Spec       = Get-Content $_ -Raw
            $OldVersion = ([Regex]".*<[vV]ersion>(.*)</[vV]ersion>").Match($Spec).Groups[1].Value
            $Spec.Replace($OldVersion, $Version) | Set-Content $_ -Force
        }
    }
}