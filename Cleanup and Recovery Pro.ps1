<#
    Created by Mathew Pittard (TVDOfficial)
	This script simplifies system cleanup and user profile management. 
	It lets you create restore points, empty the recycle bin, and delete temporary files in just one click.
	You can also manage user profiles through a user-friendly interface, easily selecting and removing profiles. 
	The script also displays free space on your system drive and the total space saved after cleanup functions.
#>


# Check if script is being ran as administrator
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script must be run as an administrator. Restarting script with administrator privileges..."
    # Restart script as administrator
    Start-Process powershell -Verb runAs -ArgumentList "-File `"$PSCommandPath`""
    exit
}

try {
    # Load necessary assemblies
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement

    function Get-XamlContent {
        return @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    x:Name="Window" Title="Cleanup and Recovery Pro" Width="600" Height="400">
    <Grid>
        <Button x:Name="CreateRestorePoint" Content="Create Restore Point" HorizontalAlignment="Left" Margin="30,10,0,0" VerticalAlignment="Top" Width="150" Height="30" />
        <Button x:Name="EmptyRecycleBin" Content="Empty Recycle Bins" HorizontalAlignment="Left" Margin="195,10,0,0" VerticalAlignment="Top" Width="150" Height="30" />
        <Button x:Name="DeleteTempFiles" Content="Delete Temp Files" HorizontalAlignment="Left" Margin="360,10,0,0" VerticalAlignment="Top" Width="150" Height="30" />
        <ListView x:Name="UserProfiles" HorizontalAlignment="Left" Margin="10,50,0,0" VerticalAlignment="Top" Width="500" Height="250">
            <ListView.View>
                <GridView>
                    <GridViewColumn Width="40" Header="Select">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <CheckBox IsChecked="{Binding IsSelected}" />
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Width="150" Header="Username">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <TextBlock Text="{Binding Username}">
                                    <TextBlock.Style>
                                        <Style TargetType="TextBlock">
                                            <Style.Triggers>
                                                <DataTrigger Binding="{Binding ADStatus}" Value="Active">
                                                    <Setter Property="Foreground" Value="Green" />
                                                </DataTrigger>
                                                <DataTrigger Binding="{Binding ADStatus}" Value="Disabled">
                                                    <Setter Property="Foreground" Value="Red" />
                                                </DataTrigger>
                                            </Style.Triggers>
                                        </Style>
                                    </TextBlock.Style>
                                </TextBlock>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Width="150" Header="AD Status">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <TextBlock Text="{Binding ADStatus}">
                                    <TextBlock.Style>
                                        <Style TargetType="TextBlock">
                                            <Style.Triggers>
                                                <DataTrigger Binding="{Binding ADStatus}" Value="Active">
                                                    <Setter Property="Foreground" Value="Green" />
                                                </DataTrigger>
                                                <DataTrigger Binding="{Binding ADStatus}" Value="Disabled">
                                                    <Setter Property="Foreground" Value="Red" />
                                                </DataTrigger>
                                            </Style.Triggers>
                                        </Style>
                                    </TextBlock.Style>
                                </TextBlock>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                </GridView>
            </ListView.View>
        </ListView>
        <Button x:Name="RemoveProfile" Content="Remove Profile" HorizontalAlignment="Left" Margin="360,310,0,0" VerticalAlignment="Top" Width="150" Height="30" />
        <TextBlock x:Name="SpaceInfo" Margin="10,320,0,0" Width="300" Height="30" />
		<TextBlock x:Name="SavedSpaceInfo" HorizontalAlignment="Left" Margin="147,340,0,0" VerticalAlignment="Top" Width="150" Height="30" />

    </Grid>
</Window>
"@
    }

    # Load XAML
    [xml]$xaml = Get-XamlContent
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $Window = [Windows.Markup.XamlReader]::Load($reader)

    # Define button actions
    $CreateRestorePoint = $Window.FindName('CreateRestorePoint')
    $EmptyRecycleBin = $Window.FindName('EmptyRecycleBin')
    $DeleteTempFiles = $Window.FindName('DeleteTempFiles')
    $RemoveProfile = $Window.FindName('RemoveProfile')
    $UserProfiles = $Window.FindName('UserProfiles')
	
	$totalSavedSpace = 0
	$totalSavedSpaceGB = 0
	

    # Functions
	
	function Update-SpaceInfo {
    $drive = Get-PSDrive -Name "C"
    $freeSpace = $drive.Free
    $totalSpace = $drive.Used + $freeSpace
    $freeSpaceTB = [math]::Round($freeSpace / 1TB, 2)
    $freeSpaceGB = [math]::Round($freeSpace / 1GB, 2)
    $totalSpaceTB = [math]::Round($totalSpace / 1TB, 2)

    if ($totalSpaceTB -lt 1) {
        $Window.FindName('SpaceInfo').Text = "Free space: $freeSpaceGB GB"
    } else {
        $Window.FindName('SpaceInfo').Text = "Free space: $freeSpaceTB TB"
    }
	
    if ($totalSavedSpace -lt 1) {
        $Window.FindName('SavedSpaceInfo').Text = "Total saved space: $totalSavedSpaceGB GB"
    } else {
        $Window.FindName('SavedSpaceInfo').Text = "Total saved space: $totalSavedSpaceTB TB"
    }
}

    function Invoke-ActionAndUpdateSpaceInfo($action) {
        $beforeFreeSpace = (Get-PSDrive -Name "C").Free
        &$action
        $afterFreeSpace = (Get-PSDrive -Name "C").Free
        $savedSpace = $afterFreeSpace - $beforeFreeSpace
        Update-SpaceInfo

        # Update the total saved space
        $script:totalSavedSpace += $savedSpace
        $totalSavedSpaceGB = [math]::Round($script:totalSavedSpace / 1GB, 2)
        $Window.FindName('SavedSpaceInfo').Text = "Total saved space: $totalSavedSpaceGB GB"
    }
	
	function UpdateRestorepointFrequencyLimit {
    $registryPath = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $registryValueName = 'SystemRestorePointCreationFrequency'
    $customFrequencyInMinutes = 1 # Set the custom frequency value in minutes

    try {
        # Check if the registry key exists and its value is not already set to 5 minutes
        if ((Test-Path -Path $registryPath) -and ((Get-ItemProperty -Path $registryPath -Name $registryValueName -ErrorAction SilentlyContinue).$registryValueName -ne $customFrequencyInMinutes)) {
            # Set the custom frequency value
            Set-ItemProperty -Path $registryPath -Name $registryValueName -Value $customFrequencyInMinutes -Type DWord -Force
            Write-Host "Successfully updated the system restore point creation frequency to $customFrequencyInMinutes minutes."
        } else {
            Write-Host "The system restore point creation frequency is already set to $customFrequencyInMinutes minute(s). - No need to update"
        }
    } catch {
        Write-Warning "An error occurred while updating the registry: $_"
    }
}

	
    function Get-ADUserStatus {
        param($username)
        try {
            $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain')
            $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($context, $username)
            if ($user -ne $null) {
                if ($user.Enabled -eq $true) {
                    return "Active" 
                } else {
                    return "Disabled"
                }
            }
            return "N/A"
        } catch {
            Write-Warning "Error getting AD user status for $($username): $_"
            return "Error"
        }
    }


    function Load-UserProfiles {
    try {
        Get-WmiObject -Class Win32_UserProfile | ForEach-Object {
            $sidObj = New-Object System.Security.Principal.SecurityIdentifier($_.SID)
            try {
                $username = ($sidObj.Translate([System.Security.Principal.NTAccount])).Value
            } catch {
                Write-Warning "Error translating SID for $($sidObj.Value): $_"
                return
            }

            if ($username -ne $null) {
                $adStatus = Get-ADUserStatus -Username $username
                $UserProfiles.Items.Add([PSCustomObject]@{IsSelected=$false; Username=$username; ADStatus=$adStatus})
            }
        }
    } catch {
        Write-Warning "Error loading user profiles: $_"
    }
}


    # Event Handlers
    $CreateRestorePoint.Add_Click({
    try {
        # Create restore point
        Checkpoint-Computer -Description "Created by Cleanup and Recovery Pro" -RestorePointType "MODIFY_SETTINGS"
        [System.Windows.MessageBox]::Show('Restore point created successfully.')
    } catch {
        [System.Windows.MessageBox]::Show("Error creating restore point: $_")
    }
})

    $EmptyRecycleBin.Add_Click({
    Invoke-ActionAndUpdateSpaceInfo -action {
        try {
            # Create a new process object for running the command prompt as administrator
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = 'cmd.exe'
            $psi.Arguments = '/c rd /s /q c:\$Recycle.Bin' # Add the /q option to force "yes" to any confirmation prompts
            $psi.Verb = 'runas'
            $psi.WindowStyle = 'Hidden'
            
            # Start the command prompt process as administrator
            $process = [System.Diagnostics.Process]::Start($psi)
            $process.WaitForExit()
            
            [System.Windows.MessageBox]::Show('Recycle bins emptied successfully.')
        } catch {
            [System.Windows.MessageBox]::Show("Error emptying recycle bins: $_")
        }
    }
})
    $DeleteTempFiles.Add_Click({
        Invoke-ActionAndUpdateSpaceInfo -action {
            Get-ChildItem -Path $env:TEMP -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            [System.Windows.MessageBox]::Show('Temp files deleted successfully.')
        }
    })

$RemoveProfile.Add_Click({
    Invoke-ActionAndUpdateSpaceInfo -action {
        $selectedProfiles = $UserProfiles.Items | Where-Object { $_.IsSelected }
        foreach ($profile in $selectedProfiles) {
            $userName = $profile.Username.Split('\')[-1]
            $userProfile = Get-WmiObject -Class Win32_UserProfile -Filter "LocalPath like '%$userName%'"
            if ($userProfile) {
                $userFolderPath = $userProfile.LocalPath
                $userSID = $userProfile.SID
                
                $userProfile | Remove-WmiObject
                $UserProfiles.Items.Remove($profile)
                
                # Delete the user's folder
                if (Test-Path $userFolderPath) {
                    Remove-Item -Path $userFolderPath -Force -Recurse
                }
                
                # Delete the registry entry for the profile
                $profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSID"
                if (Test-Path $profileListPath) {
                    Remove-Item -Path $profileListPath -Force
                }
                
                [System.Windows.MessageBox]::Show("($profile.Username)'s profile and folder were removed successfully!")
            } else {
                [System.Windows.MessageBox]::Show("Error: could not find profile for $($profile.Username)")
            }
        }
        [System.Windows.MessageBox]::Show('All selected profiles and folders were removed successfully!')
    }
})


    # Initialize
    Load-UserProfiles
	UpdateRestorepointFrequencyLimit
    Update-SpaceInfo

    # Run the application
    [System.Windows.Interop.WindowInteropHelper]::new($Window).EnsureHandle()
    $Window.ShowDialog() | Out-Null
} catch {
    Write-Warning "An error occurred: $_"
}

