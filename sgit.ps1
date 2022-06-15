Param
(
    [Parameter(Mandatory=$true, Position=0)]
    [String] $Command
)
DynamicParam
{
    $ParamDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    Function Add-InputParameter
    {
        Param
        (
            [Parameter(Position=0)]
            [String] $Name,

            [Parameter(Position=1)]
            [Type] $Type,

            [Switch] $Mandatory
        )

        $paramAttribute = [System.Management.Automation.ParameterAttribute] @{
            ParameterSetName = $Command.ToLower()
            Mandatory = $Mandatory.IsPresent
        }

        $paramAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
        $paramAttributeCollection.Add($paramAttribute)

        $newParam = [System.Management.Automation.RuntimeDefinedParameter]::new(
            $Name, $Type, $paramAttributeCollection
        )

        $ParamDictionary.Add($Name, $newParam)
    }

    if ($Command -iin @('hceckout', 'cehckout'))
    {
        Write-Warning "$Command == checkout"
        $Command = 'checkout'
    }

    Add-InputParameter 'NonInteractive' ([Switch])

    switch ($Command)
    {
        { $_ -ieq 'checkout' -or $_ -ieq 'update-branch' -or $_ -ieq 'delete' -or $_ -ieq 'release-branch' -or $_ -ieq 'release-exact-branch' }
        {
            Add-InputParameter 'SourceName' ([String])
        }
        { $_ -ieq 'checkout' -or $_ -ieq 'update-branch' -or $_ -ieq 'delete' -or $_ -ieq 'release-branch' }
        {
            Add-InputParameter 'Type' ([String]) -Mandatory
            Add-InputParameter 'WorkItemNumber' ([String]) -Mandatory
            Add-InputParameter 'Title' ([String]) -Mandatory
            Add-InputParameter 'Username' ([String])
        }
        { $_ -ieq 'checkout' -or $_ -ieq 'update-branch' -or $_ -ieq 'delete' }
        {
            Add-InputParameter 'SourceBranch' ([String])
        }
        { $_ -ieq 'release-branch' -or $_ -ieq 'release-exact-branch' }
        {
            Add-InputParameter 'ReleaseBranch' ([String])
            Add-InputParameter 'MergeOnly' ([Switch])
            Add-InputParameter 'CleanupOnly' ([Switch])
        }
        { $_ -ieq 'delete' }
        {
            Add-InputParameter 'Remote' ([Switch])
        }
        { $_ -ieq 'release-exact-branch' }
        {
            Add-InputParameter 'FeatureBranch' ([String]) -Mandatory
        }
        { $_ -ieq 'create-pr' }
        {
            Add-InputParameter 'Organization' ([String]) -Mandatory
            Add-InputParameter 'Project' ([String]) -Mandatory
            Add-InputParameter 'RepoName' ([String]) -Mandatory
        }
        { $_ -ieq 'close-release' }
        {
            Add-InputParameter 'Version' ([String]) -Mandatory
            Add-InputParameter 'ReleaseBranch' ([String])
        }
    }

    return $ParamDictionary
}
Process
{
    function Invoke-SgitCommand
    {
        Param
        (
            [Array] $ArgumentList,

            [Switch] $AllowFail
        )

        $commandString = "git $($ArgumentList -join ' ')"
        Write-Host "git $($ArgumentList -join ' ')" -ForegroundColor Cyan

        $proc = Start-Process -FilePath "git" -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow
        
        if (-not $AllowFail.IsPresent -and $proc.ExitCode -ne 0)
        {
            Write-Host "[Error] Failed last command" -ForegroundColor Red
            exit 1
        }
    }

    function Import-ADOPSModule
    {
        if (-not (Get-Module 'ADOPS'))
        {
            try
            {
                Import-Module 'ADOPS' -ErrorAction Stop
            }
            catch
            {
                Write-Host 'Unable to import required module: ADOPS.' -ForegroundColor Red
                exit 1
            }
        }
    }

    $NonInteractive = $PSBoundParameters.NonInteractive

    switch ($Command)
    {
        { $_ -ieq 'checkout' -or $_ -ieq 'update-branch' -or $_ -ieq 'delete' -or $_ -ieq 'release-branch' -or $_ -ieq 'release-exact-branch' }
        {
            $SourceName = $PSBoundParameters.SourceName

            if (-not $SourceName)
            {
                $SourceName = 'origin'
            }
        }
        { $_ -ieq 'checkout' -or $_ -ieq 'update-branch' -or $_ -ieq 'delete' -or $_ -ieq 'release-branch' }
        {
            $Type = $PSBoundParameters.Type.ToLower()
            $WorkItemNumber = $PSBoundParameters.WorkItemNumber
            $Title = $PSBoundParameters.Title
            $Username = $PSBoundParameters.Username

            if (-not $Username)
            {
                $Username = [Environment]::Username.ToLower()
            }

            $FeatureBranch = "$Type/$WorkItemNumber/$Title"
            $DevBranch = "dev/$Username/$WorkItemNumber/$Title"
        }
        { $_ -ieq 'checkout' -or $_ -ieq 'update-branch' }
        {
            $SourceBranch = $PSBoundParameters.SourceBranch

            if (-not $SourceBranch)
            {
                $SourceBranch = 'main'
            }
        }
        { $_ -ieq 'release-branch' -or $_ -ieq 'release-exact-branch' -or $_ -ieq 'close-release' }
        {
            $ReleaseBranch = $PSBoundParameters.ReleaseBranch

            if (-not $ReleaseBranch)
            {
                $ReleaseBranch = 'release/vNext'
            }
        }
        { $_ -ieq 'release-branch' -or $_ -ieq 'release-exact-branch' }
        {
            $MergeOnly = $PSBoundParameters.MergeOnly
            $CleanupOnly = $PSBoundParameters.CleanupOnly
        }
        'delete'
        {
            $Remote = $PSBoundParameters.Remote
        }
        'release-exact-branch'
        {
            $FeatureBranch = $PSBoundParameters.FeatureBranch
        }
        { $_ -ieq 'checkout' -or $_ -ieq 'update-branch' }
        {
            # checkout the source branch
            # if checkout, is the branches upstream branch
            # if delete, ensures the branch being deleted isn't checked out
            Invoke-SgitCommand -ArgumentList "checkout", "$SourceBranch"
            Invoke-SgitCommand -ArgumentList "pull"
        }
        'checkout'
        {
            Invoke-SgitCommand -ArgumentList "checkout", "-b", "`"$FeatureBranch`""
            Invoke-SgitCommand -ArgumentList "push", "--set-upstream", "`"$SourceName`"", "`"$FeatureBranch`"" 

            Invoke-SgitCommand -ArgumentList "checkout", "-b", "`"$DevBranch`""
            Invoke-SgitCommand -ArgumentList "push", "--set-upstream", "`"$SourceName`"", "`"$DevBranch`""
            break
        }
        'update-branch'
        {
            Invoke-SgitCommand -ArgumentList "checkout", "`"$FeatureBranch`""
            Invoke-SgitCommand -ArgumentList "pull", "`"$SourceName`"", "`"$SourceBranch`""
            Invoke-SgitCommand -ArgumentList "push"

            Invoke-SgitCommand -ArgumentList "checkout", "`"$DevBranch`""
            Invoke-SgitCommand -ArgumentList "pull", "`"$SourceName`"", "`"$FeatureBranch`""
            Invoke-SgitCommand -ArgumentList "push"
            break
        }
        { $_ -ieq 'release-branch' -or $_ -ieq 'release-exact-branch' }
        {
            if (-not $CleanupOnly.IsPresent)
            {
                Invoke-Sgitcommand -ArgumentList "checkout", "`"$ReleaseBranch`""
                Invoke-Sgitcommand -ArgumentList "pull"

                Invoke-Sgitcommand -ArgumentList "checkout", "`"$FeatureBranch`""
                Invoke-Sgitcommand -ArgumentList "pull"

                Invoke-Sgitcommand -ArgumentList "pull", "`"$SourceName`"", "`"$ReleaseBranch`""
                Invoke-Sgitcommand -ArgumentList "push"

                if (-not $NonInteractive.IsPresent)
                {
                    Write-Host "Complete the pull request in Azure DevOps."
                    $command = Read-Host "Press Enter to when completed..."
                    $SourceBranch = $ReleaseBranch
                }
            }
        }
        { $_ -ieq 'delete' -or $_ -ieq 'release-branch' -or $_ -ieq 'release-exact-branch' } 
        {
            if (-not $MergeOnly.IsPresent)
            {
                if ($SourceBranch)
                {
                    Invoke-SgitCommand -ArgumentList "checkout", "`"$SourceBranch`""
                    Invoke-SgitCommand -ArgumentList "pull"
                }

                if ($DevBranch)
                {
                    if ($Command -ne 'delete' -or $Remote.IsPresent)
                    {
                        Invoke-SgitCommand -ArgumentList "push", "`"$SourceName`"", "`":$DevBranch`"" -AllowFail
                    }

                    Invoke-SgitCommand -ArgumentList "branch", "-D", "`"$DevBranch`"" -AllowFail
                }

                if ($FeatureBranch)
                {
                    if ($Command -ne 'delete' -or $Remote.IsPresent)
                    {
                        Invoke-SgitCommand -ArgumentList "push", "`"$SourceName`"", "`":$FeatureBranch`"" -AllowFail
                    }

                    Invoke-SgitCommand -ArgumentList "branch", "-D", "`"$FeatureBranch`"" -AllowFail
                }
            }
            break
        }
        { $_ -ieq 'create-pr' }
        {
            Import-ADOPSModule

            Write-Host 'stop'
            exit 1

            if (-not $Organization)
            {
                # Parse from origin?
                $Organization = $null
            }

            if (-not $Project)
            {
                # Parse from origin?
                $Project = $null
            }

            if (-not $SourceBranch)
            {
                # Parse from .git / HEAD
                $SourceBranch = $null
            }

            if (-not $TargetBranch)
            {
                # If SourceBranch is dev, TargetBranch is feature
                # If SourceBranch is feature, TargetBranch is ReleaseBranch
                $TargetBranch = $null
            }

            New-AdoPullRequest `
                -Organization $Organization `
                -Project $Project `
                -RepoName $RepoName `
                -Title $Title `
                -SourceBranch $SourceBranch `
                -TargetBranch $TargetBranch
        }
        { $_ -ieq 'close-release' }
        {
            # Look for PR to close

            Invoke-SgitCommand -ArgumentList "fetch"
            Invoke-SgitCommand -ArgumentList "checkout", "main"
            Invoke-SgitCommand -ArgumentList "pull"
            Invoke-SgitCommand -ArgumentList "tag", "-a", "v$Version", "-m", """Guardian Cli Release v$Version"""
            Invoke-SgitCommand -ArgumentList "push", "--follow-tags"
            Invoke-SgitCommand -ArgumentList "branch", "-D", $ReleaseBranch
            Invoke-SgitCommand -ArgumentList "push", "origin", ":$ReleaseBranch"
            Invoke-SgitCommand -ArgumentList "checkout", "-b", $ReleaseBranch
            Invoke-SgitCommand -ArgumentList "push", "--set-upstream", "origin", $ReleaseBranch
        }
        default
        {
            Write-Error "Command is not supported: $Command"
            break
        }
    }
}