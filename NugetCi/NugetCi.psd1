@{
    RootModule = 'NugetCi.psm1';
    Description = 'Nuget Packages CI (Version Step, Push, Pack, etc.)'
    ModuleVersion = '0.1.10';
    GUID = '5062872f-4893-4c22-ac55-0f631121bfc0';
    Author = 'NBCUniversal LLC.';
    CompanyName = 'NBCUniversal LLC.';
    FunctionsToExport = @(
        'Invoke-NugetCiVersionStepper',
        'Get-NugetCiLatestPackageVersion',
        'Invoke-NugetCiPack',
        'Invoke-NugetCiPush',
        'Invoke-NugetCiInstall',
        'Invoke-NugetCi'
    );
    CmdletsToExport = '';
    VariablesToExport = '';
    AliasesToExport = @();
    PrivateData = @{
        PSData = @{
            LicenseUri = 'https://github.com/galicea-gn/NugetCi/blob/master/LICENSE'
            ProjectUri = 'https://github.com/galicea-gn/NugetCi'
            IconUri = ''
            CommitHash = '[[COMMIT_HASH]]'
        }
    }
    DefaultCommandPrefix = ''
}
