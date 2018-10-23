
function Get-SteppedNugetVersion
{
    <#
    .SYNOPSIS
        Steps the version of a nuget package
    .PARAMETER BasePath
        Version that will be stepped.        
    .PARAMETER Patch
        Optional. New patch to use if default increment is being bypassed.
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True, Position=0)]
        [String]$Version,

        [Parameter(Mandatory=$False, Position=1)]
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
    <#
    .SYNOPSIS
        Get newest version of NuGet package
    .DESCRIPTION
        Makes a request to the provided NuGet feed with the package's id to retrieve the latest, real-time version currently avaiable.
        Given the fact that we do not handle differences in promotions, etc., this will retrieve ONLY 'release' packages.
    .PARAMETER UrlBase
        Url scheme, host, and port portions of the nuget feed. Url defaults to https since NuGet does not support http
    .PARAMETER NugetPackageId
        Package Id of the package whose version we are retrieving
    .PARAMETER Credential
        Optional. PSCredential to use to authenticate with the NuGet feed.
    #>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True, Position=0)]
        [Alias('base', 'host', 'ub')]
        [String]$UrlBase,

        [Parameter(Mandatory=$True, Position=1)]
        [Alias('n', 'name')]
        [String]$FeedName,

        [Parameter(
            Mandatory=$True, 
            Position=2,
            ValueFromPipeline=$True,
            ValueFromPipelineByPropertyName=$True
        )]
        [Alias('package', 'p', 'pack', 'id')]
        [String]$NuGetPackageId,

        [Parameter(Mandatory=$False, Position=2)]
        [PSCredential]$Credential
    )
    
    Begin {
        if ($UrlBase -Contains 'https') {
            add-type @"
                using System.Net;
                using System.Security.Cryptography.X509Certificates;
                public class TrustAllCertsPolicy : ICertificatePolicy {
                    public bool CheckValidationResult(
                        ServicePoint srvPoint, X509Certificate certificate,
                        WebRequest request, int certificateProblem) {
                        return true;
                    }
                }
"@
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        }
    }
    Process {
        $FeedUrl   = "$UrlBase/nuget/$FeedName/Packages()?`$filter=Id%20eq%20'$NuGetPackageId'"
        $WebClient = New-Object System.Net.WebClient
        
        if ($Null -ne $Credential) {
            $Basic = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Credential.GetNetworkCredential().UserName):$($Credential.GetNetworkCredential().Password)"));
            $webClient.Headers["Authorization"] = "Basic $basic"
        }
        
        $QueryResults = [xml]($WebClient.DownloadString($FeedUrl))
        $Version      = $QueryResults.Feed.Entry | 
                        Sort-Object -Property id -Descending |
                        ForEach-Object { $_.Properties.Version } |
                        Select-Object -First 1
        
        if (!$Version) {
            $Version = "0.0.0.0"
        }
        
        return $Version
    }
}

function Invoke-NugetCiVersionStepper
{
    <#
    .SYNOPSIS
        Steps the version of a nuget package
    .DESCRIPTION
        For each .nuspec found recursively in the $BasePath:
        Makes a request to the provided NuGet feed with the package's id to retrieve the latest, real-time version currently avaiable.
        Then replaces the version in the .nuspec for this package with the latest version, incrementing patch by 1.
    .PARAMETER BasePath
        Directory to use as the base path of the version stepping.        
    .PARAMETER UrlBase
        Url host and port portions of the nuget feed. Url defaults to https. Might be changed in the future.
    .PARAMETER Credential
        Optional. PSCredential to use to authenticate with the NuGet feed.
    .PARAMETER Patch
        Optional. Specifies a patch version to use instead of the default increment of 1.
    .PARAMETER NugetPackageId
        Nuget package id if CI is being executed for a single package.
    .PARAMETER NuspecPath
        Path to $NugetPackageId's .nuspec.
    #>

    [CmdletBinding(DefaultParameterSetName='MultiPackage')]
    Param (
        [Parameter(
            Mandatory=$True, 
            Position=0,
            ParameterSetName='MultiPackage'
        )]
        [ValidateScript({ Test-Path $_ -PathType Directory })]
        [Alias('bp', 'p', 'path')]
        [String]$BasePath,

        [Parameter(
            Mandatory=$True, 
            Position=1,
            ParameterSetName='SinglePackage'
        )]
        [Parameter(
            Mandatory=$True, 
            Position=1,
            ParameterSetName='MultiPackage'
        )]
        [Alias('base', 'host', 'ub')]
        [String]$UrlBase,

        [Parameter(
            Mandatory=$False, 
            Position=2,
            ParameterSetName='SinglePackage'
        )]
        [Parameter(
            Mandatory=$False, 
            Position=2,
            ParameterSetName='MultiPackage'
        )]
        [PSCredential]$Credential,

        [Parameter(
            Mandatory=$False, 
            Position=3,
            ParameterSetName='SinglePackage'
        )]
        [Parameter(
            Mandatory=$False, 
            Position=3,
            ParameterSetName='MultiPackage'
        )]
        [String]$Patch,

        [Parameter(
            Mandatory=$True, 
            Position=4,
            ParameterSetName='SinglePackage',
            ValueFromPipeline=$True,
            ValueFromPipelineByPropertyName=$True
        )]
        [Alias('package', 'pack', 'id')]
        [String]$NugetPackageId,

        [Parameter(
            Mandatory=$True, 
            Position=5,
            ParameterSetName='SinglePackage'
        )]
        [ValidateScript({ Test-Path $_ -PathType File })]
        [Alias('np', 'spec')]
        [String]$NuspecPath
    )

    Process {
        if ($PsCmdlet.ParameterSetName = 'SinglePackage') {
            $LastVersion  = Get-NugetCiLatestPackageVersion $UrlBase $_ $Credential
            $Version      = Get-SteppedNugetVersion $LastVersion $Patch
            $Spec         = Get-Content $NuspecPath -Raw
            $OldVersion   = ([Regex]".*<[vV]ersion>(.*)</[vV]ersion>").Match($Spec).Groups[1].Value
            $Spec.Replace($OldVersion, $Version) | Set-Content $NuspecPath -Force
        }
        else {
            $BasePath   = Resolve-Path $BasePath
            $Nuspecs = (Get-ChildItem $BasePath -Recurse -Include '*.nuspec').FullName | ForEach-Object { Split-Path (Split-Path $_ -Parent) -Leaf }
        
            $Nuspecs | ForEach-Object {
                $LastVersion  = Get-NugetCiLatestPackageVersion $UrlBase $_ $Credential
                $Version      = Get-SteppedNugetVersion $LastVersion $Patch
                $Package      = Get-ChildItem $BasePath -Include "$($_).nuspec" -Recurse
        
                $Package | ForEach-Object { 
                    $Spec       = Get-Content $_ -Raw
                    $OldVersion = ([Regex]".*<[vV]ersion>(.*)</[vV]ersion>").Match($Spec).Groups[1].Value
                    $Spec.Replace($OldVersion, $Version) | Set-Content $_ -Force
                }
            }
        }
    }
}

function Invoke-NugetCiPack
{
    <#
    .SYNOPSIS
        Performs NuGet pack for the designated packages.
    .DESCRIPTION
        For each .nupkg found recursively in the $BasePath:
        Packs the .nupkg.
        Or, does this for the single package specified
    .PARAMETER BasePath
        Directory to use as the base path of the packing.
    .PARAMETER NuspecPath
        Path to .nuspec to pack.
    .PARAMETER BootStrap
        Optional. Speicfies whether or not to install NuGet if it is not found.
    #>

    [CmdletBinding(DefaultParameterSetName='MultiPackage')]
    Param (
        [Parameter(
            Mandatory=$True, 
            Position=0,
            ParameterSetName='MultiPackage'    
        )]
        [ValidateScript({ Test-Path $_ -PathType Directory })]
        [Alias('bp', 'p', 'path')]
        [String]$BasePath,

        [Parameter(
            Mandatory=$True, 
            Position=1,
            ParameterSetName='SinglePackage'
        )]
        [ValidateScript({ Test-Path $_ -PathType File })]
        [Alias('np', 'spec')]
        [String]$NuspecPath,

        [Parameter(Mandatory=$False, Position=2)]
        [Switch]$BootStrap
    )

    Begin {
        if (!(Get-Command nuget.exe -ListAvailable) -And !$BootStrap) {
            Throw "Nuget not found and bootstrap option not set. Please Install the NuGet executable or re-run with the BootStrap switch enabled."
        }
        elseif (!(Get-Command nuget.exe -ListAvailable)) {
            Invoke-NugetCiInstall
        }
    }
    Process {
        if ($PsCmdlet.ParameterSetName = 'SinglePackage') {
            Invoke-Expression "nuget pack $NuspecPath"
        }
        else {
            $BasePath = Resolve-Path $BasePath
            (Get-ChildItem $BasePath -Recurse -Include '*.nuspec').FullName | 
            ForEach-Object { Split-Path (Split-Path $_ -Parent) -Leaf } | 
            ForEach-Object {
                Invoke-Expression "nuget pack $($_)"
            }
        }
    }
}

function Invoke-NugetCiPush
{
    <#
    .SYNOPSIS
        Performs NuGet push for the designated packages.
    .DESCRIPTION
        For each .nupkg found recursively in the $BasePath:
        Pushes the .nupkg.
        Or, does this for the single package specified
    .PARAMETER BasePath
        Directory to use as the base path of the pushing.        
    .PARAMETER Source
        Url of the nuget feed, or name of configured source.
    .PARAMETER Credential
        Optional. PSCredential to use to authenticate with the NuGet feed.
    .PARAMETER NupkgPath
        Path to .nupkg to push.
    .PARAMETER BootStrap
        Optional. Speicfies whether or not to install NuGet if it is not found.
    #>

    [CmdletBinding(DefaultParameterSetName='MultiPackage')]
    Param (
        [Parameter(
            Mandatory=$True, 
            Position=0,
            ParameterSetName='MultiPackage'    
        )]
        [ValidateScript({ Test-Path $_ -PathType Directory })]
        [Alias('bp', 'p', 'path')]
        [String]$BasePath,

        [Parameter(
            Mandatory=$True, 
            Position=1,
            ParameterSetName='SinglePackage'
        )]
        [Parameter(
            Mandatory=$True, 
            Position=1,
            ParameterSetName='MultiPackage'
        )]
        [Alias('base', 'host', 'ub')]
        [String]$Source,

        [Parameter(
            Mandatory=$False, 
            Position=2,
            ParameterSetName='SinglePackage'
        )]
        [Parameter(
            Mandatory=$False, 
            Position=2,
            ParameterSetName='MultiPackage'
        )]
        [PSCredential]$Credential,

        [Parameter(
            Mandatory=$True, 
            Position=3,
            ParameterSetName='SinglePackage'
        )]
        [ValidateScript({ Test-Path $_ -PathType File })]
        [Alias('np', 'pkg')]
        [String]$NupkgPath,

        [Parameter(Mandatory=$False, Position=2)]
        [Switch]$BootStrap
    )

    Begin {
        if (!(Get-Command nuget.exe -ListAvailable) -And !$BootStrap) {
            Throw "Nuget not found and bootstrap option not set. Please Install the NuGet executable or re-run with the BootStrap switch enabled."
        }
        elseif (!(Get-Command nuget.exe -ListAvailable)) {
            Invoke-NugetCiInstall
        }
    }
    Process {
        $ApiKey = $Credential.GetNetworkCredential().Password

        if ($PsCmdlet.ParameterSetName = 'SinglePackage') {
            Invoke-Expression "nuget push $NupkgPath -Source $Source -ApiKey $ApiKey"
        }
        else {
            $BasePath = Resolve-Path $BasePath
            (Get-ChildItem $BasePath -Recurse -Include '*.nupkg').FullName | 
            ForEach-Object { Split-Path (Split-Path $_ -Parent) -Leaf } | 
            ForEach-Object {
                Invoke-Expression "nuget push $($_) -Source $Source -ApiKey $ApiKey"
            }
        }
    }
}

function Invoke-NugetCi
{
    <#
    .SYNOPSIS
        Performs NuGet package standard CI
    .DESCRIPTION
        For each .nuspec found recursively in the $BasePath:
        Steps the package's local nuspec version to +1 patch of latest in source, packs it, and then pushes it.
        Or does this for the single package passed by $NugetPackageId.
    .PARAMETER BasePath
        Directory to use as the base path of the version stepping, packing, and pushing.        
    .PARAMETER UrlBase
        Url host and port portions of the nuget feed. Url defaults to https.
    .PARAMETER Credential
        Optional. PSCredential to use to authenticate with the NuGet feed.
    .PARAMETER Patch
        Optional. Specifies a patch version to use instead of the default increment of 1.
    .PARAMETER NugetPackageId
        Nuget package id if CI is being executed for a single package.
    .PARAMETER NuspecPath
        Path to $NugetPackageId's .nuspec.
    #>

    [CmdletBinding(DefaultParameterSetName='MultiPackage')]
    Param (
        [Parameter(
            Mandatory=$True, 
            Position=0,
            ParameterSetName='MultiPackage'
        )]
        [ValidateScript({ Test-Path $_ -PathType Directory })]
        [Alias('bp', 'p', 'path')]
        [String]$BasePath,

        [Parameter(
            Mandatory=$True, 
            Position=1,
            ParameterSetName='SinglePackage'
        )]
        [Parameter(
            Mandatory=$True, 
            Position=1,
            ParameterSetName='MultiPackage'
        )]
        [Alias('base', 'host', 'ub')]
        [String]$UrlBase,

        [Parameter(
            Mandatory=$False, 
            Position=2,
            ParameterSetName='SinglePackage'
        )]
        [Parameter(
            Mandatory=$False, 
            Position=2,
            ParameterSetName='MultiPackage'
        )]
        [PSCredential]$Credential,

        [Parameter(
            Mandatory=$False, 
            Position=3,
            ParameterSetName='SinglePackage'
        )]
        [Parameter(
            Mandatory=$False, 
            Position=3,
            ParameterSetName='MultiPackage'
        )]
        [String]$Patch,

        [Parameter(
            Mandatory=$True, 
            Position=4,
            ParameterSetName='SinglePackage',
            ValueFromPipeline=$True,
            ValueFromPipelineByPropertyName=$True
        )]
        [Alias('package', 'pack', 'id')]
        [String]$NugetPackageId,

        [Parameter(
            Mandatory=$True, 
            Position=5,
            ParameterSetName='SinglePackage'
        )]
        [ValidateScript({ Test-Path $_ -PathType File })]
        [Alias('np', 'spec')]
        [String]$NuspecPath,

        [Parameter(Mandatory=$False, Position=6)]
        [Switch]$BootStrap
    )

    Begin {
        if (!(Get-Command nuget.exe -ListAvailable) -And !$BootStrap) {
            Throw "Nuget not found and bootstrap option not set. Please Install the NuGet executable or re-run with the BootStrap switch enabled."
        }
        elseif (!(Get-Command nuget.exe -ListAvailable)) {
            Invoke-NugetCiInstall
        }
    }
    Process {
        $Params = @{
            UrlBase        = $UrlBase
            Patch          = $Patch
            NugetPackageId = $NugetPackageId
            NuspecPath     = $NuspecPath
        }

        if ($PsCmdlet.ParameterSetName = 'SinglePackage') {
            Invoke-NugetCiVersionStepper @Params -Credential $Credential
            Invoke-NugetCiPack -NuspecPath $Params.NuspecPath

            $NupkgDir  = Split-Path (Resolve-Path $Params.NuspecPath) -Parent
            $NupkgPath = "$NupkgDir\$($Params.NugetPackageId)\$(Get-SteppedNugetVersion $LastVersion $Params.Patch).nupkg"
            Invoke-NugetCiPush -NupkgPath $NupkgPath -Source $Params.UrlBase -Credential $Credential
        }
        else {
            Invoke-NugetCiVersionStepper @Params -Credential $Credential
            Invoke-NugetCiPack -BasePath $Params.BasePath
            Invoke-NugetCiPush -BasePath $Params.BasePath -Source $Params.UrlBase -Credential $Credential
        }
    }
}

function Invoke-NugetCiInstall 
{
    <#
    .SYNOPSIS
        Installs nuget on local machine
    .DESCRIPTION
        If on Windows, retrieves nuget executable via latest version feed. Otherwise, installs nuget via the .NET Core package repository.
    .PARAMETER InstallPath
        Path to install nuget if OS is Windows. Not used if OS is Unix-flavor
    #>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$False, Position=0)]
        [String]$InstallPath="C:\Nuget"
    )

    if ([System.Environment]::OSVersion.Platform -eq 'Win32NT') {
        $SourceNugetExe = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
        $TargetNugetExe = "$InstallPath\nuget.exe"
        Invoke-WebRequest $SourceNugetExe -OutFile $TargetNugetExe
        Set-Alias nuget $TargetNugetExe -Scope Global -Verbose
        $Env:Path += ";$InstallPath\"
    }
    else {
        #TODO Assumption: if running ps core, .net core package repo is setup. Is this valid?
        if ($InstallPath -eq 'C:\Nuget') {
            $InstallPath = '\nuget'
        }
        Invoke-Expression -Command 'sudo apt install nuget'
    }
}