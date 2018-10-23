
[CmdletBinding(DefaultParameterSetName='NoCi')]
param(
    [Parameter(
        Mandatory=$False,
        Position=0,
        ParameterSetName='Ci'
    )]
    [Switch]$Ci,

    [Parameter(
        Mandatory=$True,
        Position=1,
        ParameterSetName='Ci'
    )]
    [Int32]$BuildId,

    [Parameter(
        Mandatory=$True,
        Position=2,
        ParameterSetName='Ci'
    )]
    [String]$GithubToken,

    [Parameter(
        Mandatory=$True,
        Position=2,
        ParameterSetName='Ci'
    )]
    [String]$PublishApiKey,

    [Parameter(
        Mandatory=$True,
        Position=3,
        ParameterSetName='Ci'
    )]
    [String]$PublishSource
)

Write-Verbose "Ensuring required modules are available."
if ($Ci -Or !(Get-Module -ListAvailable -Name "Pester")) {
    Install-Module -Name "Pester" -RequiredVersion "4.3.1" -Force -SkipPublisherCheck -Scope "CurrentUser" -AllowClobber
}
@( "PSScriptAnalyzer" ) | ForEach-Object {
    $MyName = $_
    if ($Null -eq (Get-Module -ListAvailable | Where-Object { $_.Name -eq $MyName })) {
        Install-Module $_ -Force -Scope "CurrentUser" -SkipPublisherCheck -AllowClobber
    }
    Import-Module $_ -Force
}

$Publish = ($Env:BUILD_SOURCEBRANCHNAME -eq "master")

<#
Write-Verbose "Running Tests..."
. "$PSScriptRoot\Tests\run.ps1"

if ($TestResults.FailedCount -gt 0) {
    Throw "Not all tests passed. Failing build..."
}
#>

Write-Verbose "Running PSScriptAnalyzer..."
(Get-ChildItem (Split-Path $PSScriptRoot -Parent) -Recurse -Include 'NugetCi.psm1', 'NugetCi.psd1').FullName | ForEach-Object {
    $AnalyzeResults = Invoke-ScriptAnalyzer -Path $_
    if ($AnalyzeResults -ne $Null) {
        Throw "$(Split-Path $_ -Leaf) did not pass PSScriptAnalyzer. Failing build..."
    }
}

if ($Ci) {
    Write-Verbose "Running CI..."
    Write-Verbose "Setting patch for all manifests..."
    (Get-ChildItem (Split-Path $PSScriptRoot -Parent) -Recurse -Include "*.psd1").FullName | ForEach-Object {
        $Manifest      = Get-Content $_ -Raw
        $OldVersion    = ([Regex]"\d*\.\d*\.\d*").Match(([Regex] "\s*ModuleVersion\s*=\s*'\d*\.\d*\.\d*';").Match($Manifest).Value).Value
        $NewVersion    = [Decimal[]] $OldVersion.Split('.')

        if ($Publish) {
            Write-Verbose "Stepping Minor..."
            $NewVersion[1]++    
        }

        $NewVersion[2] = $BuildId
        $Manifest.Replace($OldVersion, $NewVersion -Join '.') | Set-Content $_ -Force
    }

    $NewCoverage = "0%"#"$(($TestResults.CodeCoverage.NumberOfCommandsExecuted/$TestResults.CodeCoverage.NumberOfCommandsAnalyzed * 100).ToString().SubString(0, 5))%"
    $ReadMe      = Get-Content "$PSScriptRoot\README.md" -Raw

    if ($NewCoverage -ge 90) {
        $Color = "brightgreen"
    }
    elseif ($NewCoverage -ge 75) {
        $Color = "yelow"
    }
    elseif ($NewCoverage -ge 65) {
        $Color = "orange"
    }
    else {
        $Color = "red"
    }

    $ReadMe = $ReadMe.Replace(([Regex] "!\[Coverage\]\(.*\)").Match($ReadMe).Value, "![Coverage](https://img.shields.io/badge/Coverage-$($NewCoverage)25-$($Color).svg)")
    $ReadMe | Set-Content "$PSScriptRoot\README.md" -Force

    Write-Verbose "Updating ReadMe and Manifests..."
    Add-Content "$HOME\.git-credentials" "https://$($GithubToken):x-oauth-basic@github.com`n"
    Invoke-Expression -Command "git config --global credential.helper store"
    Invoke-Expression -Command "git config --global user.email nuget-ci-builder@golfchannel.lifestyle.builds.com"
    Invoke-Expression -Command "git config --global user.name nuget-ci-builder"
    Invoke-Expression -Command "git config core.autocrlf false -q"
    Invoke-Expression -Command "git checkout -b $($Env:BUILD_SOURCEBRANCHNAME) --track origin/$($Env:BUILD_SOURCEBRANCHNAME) -q"
    Invoke-Expression -Command "git pull origin $($Env:BUILD_SOURCEBRANCHNAME) -q"
    Invoke-Expression -Command "git add *.psd1"
    Invoke-Expression -Command "git add *.md"
    Invoke-Expression -Command "git commit -m '[***NO_CI***]Updating NugetCi manifests and readme' -q"
    Invoke-Expression -Command "git push -q"

    if ($Publish) {
        Write-Verbose "Publishing NugetCi to PS Gallery..."
        $Manifest = (Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) "NugetCi\NugetCi.psd1") -Raw)
        $Manifest.Replace("[[COMMIT_HASH]]", $Env:BUILD_SOURCEVERSION) | Set-Content (Join-Path (Split-Path $PSScriptRoot -Parent) "NugetCi\NugetCi.psd1") -Force
        Publish-Module -Path (Join-Path (Split-Path $PSScriptRoot -Parent) "NugetCi") -NuGetApiKey $PublishApiKey -Repository $PublishSource -Force
    }
}