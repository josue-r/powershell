param(
    $dockerUsername = "VklPQ0Rldk9wc1VzZXI=",
    $token = "Z2hwX1ZsWUQyZ1NKakJVNlVQWGhrcmJrelJuMkswcEw1eTEwMUlaMg==", # You can use an access token instead of a password
    $rollbackVersion = "", # Specify the version to roll back to
    $org = 'valvoline-llc'
)

# Decode base64-encoded variables
$decodedDockerUsername = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($dockerUsername))
$decodedToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($token))

# The script will only allow the below repositories to work 
$global:mandatoryImages = @("vioc-store-api-visit", "vioc-central-api-motor", "vioc-bottom-side-ui", "vioc-store-api-gateway")

function DockerLogin {
    param($username, $token)
    $loginCommand = "echo $token | docker login ghcr.io -u $username --password-stdin"
    Invoke-Expression $loginCommand
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully logged in to Docker.`n"
    } else {
        Write-Host "Failed to log in to Docker.`n"
        exit 1 # Exit if login fails to prevent further execution
    }
}
# Call DockerLogin function before pulling images
DockerLogin -username $decodedDockerUsername -token $decodedToken


function Get-LocaldockerImages {
    # This function uses the Docker CLI to get a list of all images and their tags from the current Docker host.
    docker images --format "{{.Repository}}:{{.Tag}}" | ForEach-Object {
        $repoAndTag = $_.Split(":") # Split each string into repository and tag based on the colon.
        $repositoryFull = $repoAndTag[0] # Select only the repository part.
        $repositoryName = $repositoryFull.Split("/")[-1] # Optionally split by '/' and select the last part if needed.
        $repositoryNameAndTag = $_.Split("/")[-1]
        if ($global:mandatoryImages -contains $repositoryName) {
            return $repositoryNameAndTag
        }
    }
}

function Get-LocalDockerContainers {
    $containers = @()
    # This function uses the Docker CLI to get a list of all containers and their statuses from the current Docker host.
    docker ps -a --format "{{.Image}};{{.Status}}" | ForEach-Object {
        $repoAndTag = $_.Split(";")
        $repositoryFull = $repoAndTag[0].Split("/")[-1]
        $repositoryName = $repositoryFull.Split("/")[-1].Split(":")[0]
        $status = $repoAndTag[-1]
        if ($global:mandatoryImages -contains $repositoryName) {
            $containers += [PSCustomObject]@{
                repositoryFull = $repositoryFull
                Status = $status
            }
        }
    }
    return $containers
}

function Get-LocalDockerContainers {
    $containers = @()
    # This function uses the Docker CLI to get a list of all containers and their statuses from the current Docker host.
    docker ps -a --format "{{.Image}};{{.Status}}" | ForEach-Object {
        $repoAndTag = $_.Split(";")
        $repositoryFull = $repoAndTag[0].Split("/")[-1]
        $repositoryName = $repositoryFull.Split("/")[-1].Split(":")[0]
        $status = $repoAndTag[-1]
        if ($global:mandatoryImages -contains $repositoryName) {
            $containers += [PSCustomObject]@{
                repositoryFull = $repositoryFull
                Status = $status
            }
        }
    }
    return $containers
}



function Get-PortMapping {
    param($repositoryName)
    switch ($repositoryName) {
        "vioc-store-api-visit" { return "4200:4000" }
        "vioc-central-api-motor" { return "9023:9023" }
        "vioc-bottom-side-ui" { return "8443:443" }
        default { return $null } # Handle cases where no mapping exists
    }
}

function Stop-Container {
    param ($existingContainer,$localTag)
    Write-Host "`nStopping and removing existing container: $existingContainer"
    docker stop $existingContainer > $null 2>$1
    while ((docker inspect -f "{{.State.Running}}" $existingContainer) -eq "true") {
        Start-Sleep -Seconds 2
    }
    Write-Host "`nContainer stopped..."
    docker rm $existingContainer > $null 2>$1
    while ((docker ps -a -f "name=$existingContainer" --format "{{.Names}}") -eq "$existingContainer") {
        Start-Sleep -Seconds 2
    }
    $status = "`nContainer: $existingContainer is removed."
    # delete old image to keep the latest ONLY in the host server
    Write-Host "Deleting local image...${existingContainer}:$localTag"
    docker rmi "ghcr.io/$org/${existingContainer}:$localTag"
    return $status
}

function Get-LatestTag {
    param($imageName, $org, $token)
    $url = "https://api.github.com/orgs/$org/packages/container/$imageName/versions"
    $headers = @{
        Authorization = "Bearer $token"
        Accept = "application/vnd.github.v3+json"
    }
    try {
        $versions = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        # Sort versions by created_at date descending to get the latest
        $latestVersion = $versions | Sort-Object -Property created_at -Descending | Select-Object -First 1
        # Extract the tags, if there are multiple tags, choose the first
        $latestTag = $latestVersion.metadata.container.tags[0]
        return $latestTag
    } catch {
        Write-Output "Failed to retrieve versions for package ${imageName}: $_"
        return $null
    }
}

# Combined function to handle stopping/removing and existing container management
function Handle-Container {
    param($repositoryName, $tag, $portMapping, $org)
    $requestedContainerAndTag = "${repositoryName}:$tag"
    #Write-Host "requestedContainerAndTag: $requestedContainerAndTag"
    $localContainers=  Get-LocalDockerContainers
    #Write-Host "localContainers: $localContainers"
    foreach ($localContainer in $localContainers) {
        #Write-Host "localContainer: $localContainer"
        $localTag = $localContainer.repositoryFull.Split(":")[1]
        if ($requestedContainerAndTag -eq $localContainer.repositoryFull -and $localContainer.Status -like "Up*") #This will evaluate if requested image is equal to local image and container status=running" 
        { 
            Write-Host "`n***`nExisting container: $($localContainer.repositoryFull) is running requested or latest image and tag. No action needed...`n***`n"
            return
        } elseif ($requestedContainerAndTag -eq $localContainer.repositoryFull -and $localContainer.Status -like "Exited*") #This will evaluate if requested image is equal to local imageand container status=stopped "
        {
            Write-Host "`n***`nExisting container: $($localContainer.repositoryFull)  is running requested image and tag but is under stopped status. Starting container...`n***`n"
            $container = $($localContainer.repositoryFull).Split(":")[0]
            Write-Host "starting container: $container"
            docker start $container
            return
        } elseif ($requestedContainerAndTag.Split(":")[0] -eq $localContainer.repositoryFull.Split(":")[0] -and $requestedContainerAndTag.Split(":")[-1] -ne $localContainer.repositoryFull.Split(":")[-1]) #This will evaluate if requested image is not equal to local image. Will stop the container ans start a new one using requested image and version
        {
            Write-Host "`n***`nExisting container: $($localContainer.repositoryFull) running using different version of requested image and tag: $requestedContainerAndTag. Stopping container...`n***`n"
            $container = $($localContainer.repositoryFull).Split(":")[0]
            $status = Stop-Container -existingContainer $container -localTag $localTag
            Write-Host $status
            Write-Host "`nStarting new container with requested image and tag: $requestedContainerAndTag ..."
            docker run -d --name "$repositoryName" -e HOSTNAME=$env:COMPUTERNAME -p $portMapping "ghcr.io/$org/${repositoryName}:$tag"
            return
        }
    }
    # Check if the requested container does not exist in the local containers
    $requestedContainerName = $requestedContainerAndTag.Split(":")[0]
    $localContainerNames = $localContainers | ForEach-Object { $_.repositoryFull.Split(":")[0] }

    if ($requestedContainerName -notin $localContainerNames) {
        Write-Host "`nNo container found: $requestedContainerName. Creating container from local image....`n"
        docker run -d --name $requestedContainerName -e HOSTNAME=$env:COMPUTERNAME -p $portMapping "ghcr.io/$org/${repositoryName}:$tag"
        return
    }
}

# Function to check if all mandatory images are present locally
function Check-MissingImages {
    param($localImages, $mandatoryImages)
    $missingImages = @()
    foreach ($image in $mandatoryImages) {
        $imageFound = $false
        foreach ($localImage in $localImages) {
            if ($localImage -like "$image*") {
                $imageFound = $true
                break
            }
        }
        if (-not $imageFound) {
            $missingImages += $image
        }
    }
    return $missingImages
}

# Function to handle rollback logic
function Handle-Rollback {
    param($rollbackVersion, $org, $token)
    $imageName = $rollbackVersion.Split(":")[0]
    $repositoryName = $imageName.Split("/")[-1]
    $tag = $rollbackVersion.Split(":")[1]
    $portMapping = Get-PortMapping -repositoryName $repositoryName
    Write-Host "Rolling back to version: $rollbackVersion"
    # Pull the rollback version image from the registry
    Write-Host "Pulling image:"
    docker pull "ghcr.io/$org/${repositoryName}:$tag"
    #call existing container function 
    Handle-Container -repositoryName $repositoryName -tag $tag -portMapping $portMapping -org $org

}
# Main logic
if ($rollbackVersion) {
    Handle-Rollback -rollbackVersion $rollbackVersion -org $org -token $decodedToken
} else {
    $dockerLocalImages = Get-LocaldockerImages
    # Check for missing images
    $missingImages = Check-MissingImages -localImages $dockerLocalImages -mandatoryImages $mandatoryImages
    foreach ($image in $missingImages) {
        $latestTag = Get-LatestTag -imageName $image -org $org -token $decodedToken
        Write-Host "Pulling missing image: $image with tag $latestTag..."
        $pullSuccess = docker pull "ghcr.io/$org/${image}:$latestTag"
        if ($pullSuccess) {
            Write-Host "Successfully pulled image: $image"
            $portMapping = Get-PortMapping -repositoryName $image
            Write-Host "Creating container for $image with port mapping $portMapping"
            docker run -d --name $image -e HOSTNAME=$env:COMPUTERNAME -p $portMapping "ghcr.io/$org/${image}:$latestTag"
        } else {
            Write-Host "Failed to pull image: $image"
        }
    }
    foreach ($image in $dockerLocalImages) {
        $localTag = $image.Split(":")[1]
        $repositoryName = $image.Split(":")[0]
        $latestTag = Get-LatestTag -imageName $repositoryName -org $org -token $decodedToken
        $portMapping = Get-PortMapping -repositoryName $repositoryName
        Handle-Container -repositoryName $repositoryName -tag $localTag -portMapping $portMapping -org $org
    }
}