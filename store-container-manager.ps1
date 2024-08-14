# Script: ComprehensiveSystemReport.ps1
# Description: Generates a comprehensive system report including disk usage, system uptime, top 5 CPU consuming processes, memory usage, network interfaces, and service status.

# Function to get disk usage
function Get-DiskUsage {
    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        [PSCustomObject]@{
            Name       = $_.Name
            UsedSpace  = ($_.Used / 1GB).ToString("F2") + " GB"
            FreeSpace  = ($_.Free / 1GB).ToString("F2") + " GB"
            TotalSpace = ($_.Used + $_.Free) / 1GB
        }
    }
}

# Function to get system uptime
function Get-SystemUptime {
    $uptime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptimeFormatted = (Get-Date) - $uptime
    [PSCustomObject]@{
        UptimeDays    = $uptimeFormatted.Days
        UptimeHours   = $uptimeFormatted.Hours
        UptimeMinutes = $uptimeFormatted.Minutes
    }
}

# Function to get top 5 CPU consuming processes
function Get-TopCPUProcesses {
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object {
        [PSCustomObject]@{
            ProcessName = $_.ProcessName
            CPUUsage    = ($_.CPU).ToString("F2") + " s"
            ID          = $_.Id
        }
    }
}

# Function to get memory usage
function Get-MemoryUsage {
    Get-CimInstance Win32_OperatingSystem | ForEach-Object {
        [PSCustomObject]@{
            TotalMemory = ($_.TotalVisibleMemorySize / 1MB).ToString("F2") + " GB"
            FreeMemory  = ($_.FreePhysicalMemory / 1MB).ToString("F2") + " GB"
            UsedMemory  = (($_.TotalVisibleMemorySize - $_.FreePhysicalMemory) / 1MB).ToString("F2") + " GB"
        }
    }
}

# Function to get network interfaces and their IP addresses
function Get-NetworkInterfaces {
    Get-NetIPAddress | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -ne '127.0.0.1' } | ForEach-Object {
        [PSCustomObject]@{
            InterfaceAlias = $_.InterfaceAlias
            IPAddress      = $_.IPAddress
            SubnetMask     = $_.PrefixLength
        }
    }
}

# Function to get status of specific services
function Get-ServiceStatus {
    $services = 'W32Time', 'Spooler', 'WinRM'  # Add more services as needed
    Get-Service -Name $services | ForEach-Object {
        [PSCustomObject]@{
            ServiceName = $_.Name
            Status      = $_.Status
            DisplayName = $_.DisplayName
        }
    }
}

# Generate the report
$diskUsageReport = Get-DiskUsage
$systemUptime = Get-SystemUptime
$topCPUProcesses = Get-TopCPUProcesses
$memoryUsage = Get-MemoryUsage
$networkInterfaces = Get-NetworkInterfaces
$serviceStatus = Get-ServiceStatus

# Path to save the report
$reportPath = "C:\Temp\ComprehensiveSystemReport.txt"

# Ensure the directory exists
$directory = [System.IO.Path]::GetDirectoryName($reportPath)
if (-not (Test-Path -Path $directory)) {
    New-Item -Path $directory -ItemType Directory -Force
}

# Save the report to a file
"Disk Usage Report:" | Out-File -FilePath $reportPath -Force
$diskUsageReport | Format-Table -AutoSize | Out-File -FilePath $reportPath -Append

"System Uptime:" | Out-File -FilePath $reportPath -Append
$systemUptime | Format-Table -AutoSize | Out-File -FilePath $reportPath -Append

"Top 5 CPU Consuming Processes:" | Out-File -FilePath $reportPath -Append
$topCPUProcesses | Format-Table -AutoSize | Out-File -FilePath $reportPath -Append

"Memory Usage Report:" | Out-File -FilePath $reportPath -Append
$memoryUsage | Format-Table -AutoSize | Out-File -FilePath $reportPath -Append

"Network Interfaces Report:" | Out-File -FilePath $reportPath -Append
$networkInterfaces | Format-Table -AutoSize | Out-File -FilePath $reportPath -Append

"Service Status Report:" | Out-File -FilePath $reportPath -Append
$serviceStatus | Format-Table -AutoSize | Out-File -FilePath $reportPath -Append

# Output to the console
Write-Output "Disk Usage Report:"
$diskUsageReport | Format-Table -AutoSize

Write-Output "System Uptime:"
$systemUptime | Format-Table -AutoSize

Write-Output "Top 5 CPU Consuming Processes:"
$topCPUProcesses | Format-Table -AutoSize

Write-Output "Memory Usage Report:"
$memoryUsage | Format-Table -AutoSize

Write-Output "Network Interfaces Report:"
$networkInterfaces | Format-Table -AutoSize

Write-Output "Service Status Report:"
$serviceStatus | Format-Table -AutoSize

# Confirmation message
Write-Output "Comprehensive system report has been saved to $reportPath"
