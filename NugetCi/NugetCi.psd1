@{
    RootModule = 'NugetCi.psm1';
    Description = 'Nuget Packages CI (Version Step, Push, Pack, etc.)'
    ModuleVersion = '0.0.1';
    GUID = '5062872f-4893-4c22-ac55-0f631121bfc0';
    Author = 'NBCUniversal LLC.';
    CompanyName = 'NBCUniversal LLC.';
    FunctionsToExport = @(
        'Invoke-NugetCiVersionStepper',
        'Get-NugetCiLatestPackageVersion'
    );
    CmdletsToExport = '';
    VariablesToExport = '';
    AliasesToExport = @();
    PrivateData = @{
        PSData = @{
            LicenseUri = ''
            ProjectUri = ''
            IconUri = ''
            CommitHash = '[[COMMIT_HASH]]'
        }
    }
    DefaultCommandPrefix = ''
}