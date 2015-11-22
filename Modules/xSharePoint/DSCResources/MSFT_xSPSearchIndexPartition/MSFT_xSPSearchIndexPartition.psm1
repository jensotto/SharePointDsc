function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]  [System.UInt32]  $Index,
        [parameter(Mandatory = $true)]  [System.String]  $Servers,
        [parameter(Mandatory = $true)]  [System.String]  $RootDirectory,
        [parameter(Mandatory = $true)]  [System.String]  $ServiceAppName,
        [parameter(Mandatory = $false)] [System.Management.Automation.PSCredential] $InstallAccount,
        [parameter(Mandatory = $true)]  [ValidateSet("Present","Absent")] [System.String] $Ensure
    )

    $result = Invoke-xSharePointCommand -Credential $InstallAccount -Arguments $PSBoundParameters -ScriptBlock {
        $params = $args[0]
        $ConfirmPreference = 'None'

        $ssa = Get-SPEnterpriseSearchServiceApplication -Identity $params.ServiceAppName 
        $indexComps = Get-SPEnterpriseSearchComponent -SearchTopology $ssa.ActiveTopology `
            | Where-Object {($_.GetType().Name -eq "IndexComponent") `
                -and ($_.IndexPartitionOrdinal -eq $params.Index)}

        if (($indexComps -eq $null) -or ($indexComps.Count -eq 0)) { return @{
            Index = -1
            Servers = $params.Servers
            RootDirectory = $null
            InstallAccount = $params.InstallAccount
            Ensure = "Absent"
        } }
        
        $servers = ""
        foreach ($indexComp in $indexComps) {
            $servers += $indexComp.ServerName + ","
        }
        
        return @{
            Index = $params.Index
            Servers = $servers.TrimEnd(",")
            RootDirectory = $params.RootDirectory
            InstallAccount = $params.InstallAccount
            Ensure = "Present"
        }
    }
    return $result
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]  [System.UInt32]  $Index,
        [parameter(Mandatory = $true)]  [System.String]  $Servers,
        [parameter(Mandatory = $true)]  [System.String]  $RootDirectory,
        [parameter(Mandatory = $true)]  [System.String]  $ServiceAppName,
        [parameter(Mandatory = $false)] [System.Management.Automation.PSCredential] $InstallAccount,
        [parameter(Mandatory = $true)]  [ValidateSet("Present","Absent")] [System.String] $Ensure
    )

    $result = Invoke-xSharePointCommand -Credential $InstallAccount -Arguments $PSBoundParameters -ScriptBlock {
        $params = $args[0]
        $ConfirmPreference = 'None'

        $ssa = Get-SPEnterpriseSearchServiceApplication -Identity $params.ServiceAppName 
        $newTopology = New-SPEnterpriseSearchTopology -SearchApplication $ssa -Clone -SearchTopology $ssa.ActiveTopology

        $servers = $params["Servers"].Replace(" ", "").Split(",", [StringSplitOptions]::RemoveEmptyEntries)

        foreach($server in $servers) {
            $ssi = Get-SPEnterpriseSearchServiceInstance -Identity $server

            if($ssi.Status -eq "Offline") {
                Write-Verbose "Start Search Service Instance on $server"
                Start-SPEnterpriseSearchServiceInstance -Identity $ssi
            }

            #Wait for Search Service Instance to come online
            $loopCount = 0
            $online = Get-SPEnterpriseSearchServiceInstance -Identity $ssi; 
            do {
                $online = Get-SPEnterpriseSearchServiceInstance -Identity $ssi; 
                Write-Verbose "Waiting for service: $($online.TypeName)"
                $loopCount++
                Start-Sleep -Seconds 30
            } 
            until ($online.Status -eq "Online" -or $loopCount -eq 20)

            if ($params.Ensure -eq "Present") {
                Write-Verbose "Creating $($params.RootDirectory) on $server"
                $networkPath = "\\$server\" + $params.RootDirectory.Replace(":\", "$\")
                New-Item $networkPath -ItemType Directory -Force
                New-SPEnterpriseSearchIndexComponent -SearchTopology $newTopology -SearchServiceInstance $ssi -IndexPartition $params.Index -RootDirectory $params.RootDirectory
            }
            else {
                $IndexComponent1 = Get-SPEnterpriseSearchComponent -SearchTopology $newTopology | ? {($_.GetType().Name -eq "IndexComponent") -and ($_.ServerName -eq $($ssi.Server.Address)) -and ($_.IndexPartitionOrdinal -eq $params.Index)}
                if($IndexComponent1) {
                    $IndexComponent1 | Remove-SPEnterpriseSearchComponent -SearchTopology $newTopology -confirm:$false
                }
            }
        }
        Set-SPEnterpriseSearchTopology -Identity $newTopology        
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]  [System.UInt32]  $Index,
        [parameter(Mandatory = $true)]  [System.String]  $Servers,
        [parameter(Mandatory = $true)]  [System.String]  $RootDirectory,
        [parameter(Mandatory = $true)]  [System.String]  $ServiceAppName,
        [parameter(Mandatory = $false)] [System.Management.Automation.PSCredential] $InstallAccount,
        [parameter(Mandatory = $true)]  [ValidateSet("Present","Absent")] [System.String] $Ensure
    )
    $CurrentValues = Get-TargetResource @PSBoundParameters
    return Test-xSharePointSpecificParameters -CurrentValues $CurrentValues -DesiredValues $PSBoundParameters -ValuesToCheck @("Ensure", "Servers")
}

Export-ModuleMember -Function *-TargetResource
