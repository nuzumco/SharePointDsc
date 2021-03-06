[CmdletBinding()]
param(
    [string] $SharePointCmdletModule = (Join-Path $PSScriptRoot "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" -Resolve)
)

$ErrorActionPreference = 'stop'
Set-StrictMode -Version latest

$RepoRoot = (Resolve-Path $PSScriptRoot\..\..\..).Path
$Global:CurrentSharePointStubModule = $SharePointCmdletModule

$ModuleName = "MSFT_SPJoinFarm"
Import-Module (Join-Path $RepoRoot "Modules\SharePointDsc\DSCResources\$ModuleName\$ModuleName.psm1") -Force

Describe "SPJoinFarm - SharePoint Build $((Get-Item $SharePointCmdletModule).Directory.BaseName)" {
    InModuleScope $ModuleName {
        $testParams = @{
            FarmConfigDatabaseName = "SP_Config"
            DatabaseServer = "DatabaseServer\Instance"
            Passphrase =  New-Object System.Management.Automation.PSCredential ("PASSPHRASEUSER", (ConvertTo-SecureString "MyFarmPassphrase" -AsPlainText -Force))
        }
        Import-Module (Join-Path ((Resolve-Path $PSScriptRoot\..\..\..).Path) "Modules\SharePointDsc")
        
        Mock Invoke-SPDSCCommand { 
            return Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $Arguments -NoNewScope
        }
        
        Remove-Module -Name "Microsoft.SharePoint.PowerShell" -Force -ErrorAction SilentlyContinue
        Import-Module $Global:CurrentSharePointStubModule -WarningAction SilentlyContinue 
        Mock Connect-SPConfigurationDatabase {}
        Mock Install-SPHelpCollection {}
        Mock Initialize-SPResourceSecurity {}
        Mock Install-SPService {}
        Mock Install-SPFeature {}
        Mock New-SPCentralAdministration {}
        Mock Install-SPApplicationContent {}
        Mock Start-Service {}
        Mock Start-Sleep {}

        $versionBeingTested = (Get-Item $Global:CurrentSharePointStubModule).Directory.BaseName
        $majorBuildNumber = $versionBeingTested.Substring(0, $versionBeingTested.IndexOf("."))

        Mock Get-SPDSCInstalledProductVersion { return @{ FileMajorPart = $majorBuildNumber } }


        Context "no farm is configured locally and a supported version of SharePoint is installed" {
            Mock Get-SPFarm { throw "Unable to detect local farm" }

            It "the get method returns null when the farm is not configured" {
                Get-TargetResource @testParams | Should BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "calls the appropriate cmdlets in the set method" {
                Set-TargetResource @testParams
                switch ($majorBuildNumber)
                {
                    15 {
                        Assert-MockCalled Connect-SPConfigurationDatabase
                    }
                    16 {
                        Assert-MockCalled Connect-SPConfigurationDatabase
                    }
                    Default {
                        throw [Exception] "A supported version of SharePoint was not used in testing"
                    }
                }
                
            }
        }

        if ($majorBuildNumber -eq 15) {
            $testParams.Add("ServerRole", "WebFrontEnd")

            Context "only valid parameters for SharePoint 2013 are used" {
                It "throws if server role is used in the get method" {
                    { Get-TargetResource @testParams } | Should Throw
                }

                It "throws if server role is used in the test method" {
                    { Test-TargetResource @testParams } | Should Throw
                }

                It "throws if server role is used in the set method" {
                    { Set-TargetResource @testParams } | Should Throw
                }
            }

            $testParams.Remove("ServerRole")
        }

        Context "no farm is configured locally and an unsupported version of SharePoint is installed on the server" {
            Mock Get-SPDSCInstalledProductVersion { return @{ FileMajorPart = 14 } }

            It "throws when an unsupported version is installed and set is called" {
                { Set-TargetResource @testParams } | Should throw
            }
        }

        Context "a farm exists locally and is the correct farm" {
            Mock Get-SPFarm { return @{ 
                DefaultServiceAccount = @{ Name = $testParams.FarmAccount.UserName }
                Name = $testParams.FarmConfigDatabaseName
            }}
            Mock Get-SPDatabase { return @(@{ 
                Name = $testParams.FarmConfigDatabaseName
                Type = "Configuration Database"
                Server = @{ Name = $testParams.DatabaseServer }
            })} 

            It "the get method returns values when the farm is configured" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns true from the test method" {
                Test-TargetResource @testParams | Should Be $true
            }
        }

        Context "a farm exists locally and is not the correct farm" {
            Mock Get-SPFarm { return @{ 
                DefaultServiceAccount = @{ Name = $testParams.FarmAccount.UserName }
                Name = "WrongDBName"
            }}
            Mock Get-SPDatabase { return @(@{ 
                Name = "WrongDBName"
                Type = "Configuration Database"
                Server = @{ Name = $testParams.DatabaseServer }
            })} 

            It "throws an error in the set method" {
                { Set-TargetResource @testParams } | Should throw
            }
        }
    }    
}