function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TypeName,

        [Parameter(Mandatory = $true)]
        [System.String[]]
        $WebApplication,

        [Parameter(Mandatory = $false)]
        [System.Boolean]
        $Enabled,

        [Parameter(Mandatory = $false)]
        [System.String]
        $Schedule,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    Write-Verbose -Message "Getting timer job settings for job '$Name'"

    $result = Invoke-SPDSCCommand -Credential $InstallAccount `
                                  -Arguments $PSBoundParameters `
                                  -ScriptBlock {
        $params = $args[0]
        
        try 
        {
            $spFarm = Get-SPFarm
        } 
        catch 
        {
            Write-Verbose -Message ("No local SharePoint farm was detected. Timer job " + `
                                    "settings will not be applied")
            return $null
        }

        $returnval = @{
            TypeName = $params.TypeName
            WebApplication = @()
        }

        if ($params.WebApplication -ne "N/A")
        {
            $enabled = ""
            $schedule = ""
            foreach ($webapp in $params.WebApplication)
            {
                $timerjob = Get-SPTimerJob -Type $params.TypeName `
                                            -WebApplication $webapp
                
                if ($timerjob.Count -eq 0)
                {
                    Write-Verbose -Message ("No timer jobs found. Please check the input values")
                    return $null
                }

                $returnval.WebApplication += $webapp
                
                if ($enabled -eq "")
                {
                    $enabled = -not $timerjob.IsDisabled
                }
                else
                {
                    if ($enabled -ne (-not $timerjob.IsDisabled))
                    {
                        $enabled = "multiple"
                    }
                }

                $jobSchedule = $timerjob.Schedule.ToString()
                if ($schedule -eq "")
                {
                    $schedule = $jobSchedule
                }
                else
                {
                    if ($schedule -ne $jobSchedule)
                    {
                        $schedule = "multiple"
                    }
                }

            }

            if ($enabled -eq "multiple")
            {
                $returnval.Enabled = $null
            }
            else
            {
                $returnval.Enabled = $enabled
            }
            
            if ($schedule -eq "multiple")
            {
                $returnval.Schedule = $null
            }
            else
            {
                $returnval.Schedule = $schedule
            }
        } 
        else 
        {
            $timerjob = Get-SPTimerJob -Type $params.TypeName
            if ($timerjob.Count -eq 1)
            {
                $returnval.WebApplication = "N/A"
                $returnval.Enabled        = -not $timerjob.IsDisabled
                $returnval.Schedule       = $null
                if ($null -ne $timerjob.Schedule) 
                {
                    $returnval.Schedule = $timerjob.Schedule.ToString()
                }
            }
            else
            {
                Write-Verbose -Message ("$($timerjob.Count) timer jobs found. Check input " + `
                               "values or use the WebApplication parameter.")
                return $null
            }
        }
    }
    return $result
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TypeName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WebApplication,

        [Parameter(Mandatory = $false)]
        [System.Boolean]
        $Enabled,

        [Parameter(Mandatory = $false)]
        [System.String]
        $Schedule,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    Write-Verbose -Message "Setting timer job settings for job '$Name'"

    Invoke-SPDSCCommand -Credential $InstallAccount `
                        -Arguments $PSBoundParameters `
                        -ScriptBlock {
        try 
        {
            $spFarm = Get-SPFarm
        } 
        catch 
        {
            throw "No local SharePoint farm was detected. Timer job settings will not be applied"
            return $null
        }
        
        Write-Verbose -Message "Start update"

        if ($params.WebApplication -ne "N/A")
        {
            foreach ($webapp in $params.WebApplication)
            {
                $timerjob = Get-SPTimerJob -Type $params.TypeName `
                                            -WebApplication $webapp
                
                if ($timerjob.Count -eq 0)
                {
                    throw ("No timer jobs found. Please check the input values")
                }
                
                if ($params.ContainsKey("Schedule") -eq $true)
                {
                    if ($params.Schedule -ne $timerjob.Schedule.ToString())
                    {
                        try 
                        {
                            Set-SPTimerJob $timerjob -Schedule $params.Schedule -ErrorAction Stop
                        } 
                        catch 
                        {
                            if ($_.Exception.Message -like `
                                "*The time given was not given in the proper format*") 
                            {
                                throw ("Incorrect schedule format used. New schedule will " + `
                                        "not be applied.")
                            } 
                            else 
                            {
                                throw ("Error occurred. Timer job settings will not be applied. " + `
                                        "Error details: $($_.Exception.Message)")
                            }
                        }
                    }
                }

                if ($params.ContainsKey("Enabled") -eq $true) 
                {
                    if ($params.Enabled -ne (-not $timerjob.IsDisabled))
                    {
                        if ($params.Enabled)
                        {
                            Write-Verbose -Message "Enable timer job $($params.TypeName)"
                            try 
                            {
                                Enable-SPTimerJob $timerjob
                            }
                            catch 
                            {
                                throw ("Error occurred while enabling job. Timer job settings will " + `
                                        "not be applied. Error details: $($_.Exception.Message)")
                                return
                            }
                        }
                        else
                        {
                            Write-Verbose -Message "Disable timer job $($params.Name)"
                            try 
                            {
                                Disable-SPTimerJob $timerjob
                            } 
                            catch 
                            {
                                throw ("Error occurred while disabling job. Timer job settings will " + `
                                        "not be applied. Error details: $($_.Exception.Message)")
                                return
                            }        
                        } 
                    }
                }
            }
        }
        else 
        {
            $timerjob = Get-SPTimerJob -Type $params.TypeName
            if ($timerjob.Count -eq 1)
            {
                if ($params.ContainsKey("Schedule") -eq $true)
                {
                    if ($params.Schedule -ne $timerjob.Schedule.ToString())
                    {
                        try 
                        {
                            Set-SPTimerJob $timerjob -Schedule $params.Schedule -ErrorAction Stop
                        } 
                        catch 
                        {
                            if ($_.Exception.Message -like `
                                "*The time given was not given in the proper format*") 
                            {
                                throw ("Incorrect schedule format used. New schedule will " + `
                                        "not be applied.")
                            } 
                            else 
                            {
                                throw ("Error occurred. Timer job settings will not be applied. " + `
                                        "Error details: $($_.Exception.Message)")
                            }
                        }
                    }
                }

                if ($params.ContainsKey("Enabled") -eq $true) 
                {
                    if ($params.Enabled -ne -not $timerjob.IsDisabled)
                    {
                        if ($params.Enabled)
                        {
                            Write-Verbose -Message "Enable timer job $($params.TypeName)"
                            try 
                            {
                                Enable-SPTimerJob $timerjob
                            }
                            catch 
                            {
                                throw ("Error occurred while enabling job. Timer job settings will " + `
                                        "not be applied. Error details: $($_.Exception.Message)")
                            }
                        }
                        else
                        {
                            Write-Verbose -Message "Disable timer job $($params.Name)"
                            try 
                            {
                                Disable-SPTimerJob $timerjob
                            } 
                            catch 
                            {
                                throw ("Error occurred while disabling job. Timer job settings will " + `
                                        "not be applied. Error details: $($_.Exception.Message)")
                            }        
                        } 
                    }
                }
            }
            else
            {
                throw ("$($timerjob.Count) timer jobs found. Check input " + `
                        "values or use the WebApplication parameter.")
            }
        }
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TypeName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WebApplication,

        [Parameter(Mandatory = $false)]
        [System.Boolean]
        $Enabled,

        [Parameter(Mandatory = $false)]
        [System.String]
        $Schedule,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    Write-Verbose -Message "Testing timer job settings for job '$Name'"

    $CurrentValues = Get-TargetResource @PSBoundParameters

    if ($null -eq $CurrentValues) 
    { 
        return $false 
    }

    return Test-SPDscParameterState -CurrentValues $CurrentValues `
                                    -DesiredValues $PSBoundParameters
}

Export-ModuleMember -Function *-TargetResource
