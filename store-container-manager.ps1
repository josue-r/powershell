param(
    $dockerUsername = "",
    $token = "", # You can use an access token instead of a password
    $rollbackVersion = "" # Specify the version to roll back to
)

function DockerLogin {
    param($username, $token)
    $loginCommand = "echo $token | docker login ghcr.io -u $username --password-stdin"
    Invoke-Expression $loginCommand
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully logged in to Docker.`n`n"
    } else {
        Write-Host "Failed to log in to Docker.`n`n"
        exit 1 # Exit if login fails to prevent further execution
    }
}

# Call DockerLogin function before pulling images
DockerLogin -username $dockerUsername -token $token

function Get-LocaldockerImages {
    $allowedRepos = @("vioc-store-api-visit", "vioc-central-api-motor", "vioc-bottom-side-ui")
    # This function uses the Docker CLI to get a list of all images and their tags from the current Docker host.
    docker images --format "{{.Repository}}:{{.Tag}}" | ForEach-Object {
        $repoAndTag = $_.Split(":") # Split each string into repository and tag based on the colon.
        $repositoryFull = $repoAndTag[0] # Select only the repository part.
        $repositoryName = $repositoryFull.Split("/")[-1] # Optionally split by '/' and select the last part if needed.
        $repositoryNameAndTag = $_.Split("/")[-1]

        if ($allowedRepos -contains $repositoryName) {
            return $repositoryNameAndTag
        }
    }
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

function Get-PortMapping {
    param($repositoryName)
    switch ($repositoryName) {
        "vioc-store-api-visit" { return "4200:4000" }
        "vioc-central-api-motor" { return "9023:9023" }
        "vioc-bottom-side-ui" { return "8443:443" }
        default { return $null } # Handle cases where no mapping exists
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

# Main logic to check Docker images against latest GHCR.io tags
$org = 'valvoline-llc'
$mandatoryImages = @("vioc-store-api-visit", "vioc-central-api-motor", "vioc-bottom-side-ui")
$dockerLocalImages = Get-LocaldockerImages
Write-Host "this is localdockerimages: $dockerLocalImages"

# Check for missing images
$missingImages = Check-MissingImages -localImages $dockerLocalImages -mandatoryImages $mandatoryImages
foreach ($image in $missingImages) {
    $latestTag = if ($rollbackVersion) { $rollbackVersion } else { Get-LatestTag -imageName $image -org $org -token $token }
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
    Write-Host "Validating tags for: $image"
    $parts = $image -split ':'
    $imageName = $parts[0]
    $localTag = $parts[1]
    $repositoryName = $imageName.Split("/")[-1]
    $latestTag = if ($rollbackVersion) { $rollbackVersion } else { Get-LatestTag -imageName $imageName -org $org -token $token }
    $portMapping = Get-PortMapping -repositoryName $repositoryName
    Write-Host "Checking ${imageName}: local tag = $localTag, latest tag = $latestTag"
    # Validate latest tag locally vs registry
    if ($localTag -eq $latestTag) { 
        Write-Host "The latest version for image: $repositoryName is installed"

        $existingContainer = docker ps -a --filter "name=$repositoryName" --filter "status=exited" --format "{{.Names}}"
        $activeContainer = docker ps -a --filter "name=$repositoryName" --filter "status=running" --format "{{.Names}}"

        if ($existingContainer -eq $repositoryName) {
            Write-Host "Container $existingContainer using latest image is stopped. Starting container... `n"
            docker start $existingContainer
        } elseif ($activeContainer -eq $repositoryName) {
            Write-Host "Existing container running latest image. No action needed... `n"
        } else {
            Write-Host "Creating container for $imageName"
            docker run -d --name "$imageName" -e HOSTNAME=$env:COMPUTERNAME -p $portMapping "ghcr.io/$org/${imageName}:$latestTag"
        }
    }
    # Pulling latest image version if host machine holds a previous version
    else {
        Write-Host "$image your version does not match the latest. Pulling latest version..."
        $pullSuccess = docker pull "ghcr.io/$org/${imageName}:$latestTag"
        if ($pullSuccess) {
            $existingContainer = docker ps -a -f "name=$imageName" --format "{{.Names}}"
            if ($existingContainer -eq "$imageName") {
                Write-Host "Stopping and removing existing container..."
                docker stop $imageName
                while ((docker inspect -f "{{.State.Running}}" $imageName) -eq "true") {
                    Start-Sleep -Seconds 2
                }
                Write-Host "Container stopped..."
                docker rm $imageName
                while ((docker ps -a -f "name=$imageName" --format "{{.Names}}") -eq "$imageName") {
                    Start-Sleep -Seconds 2
                }
                Write-Host "Container is removed."
            }
            # Delete old image
            $oldImageId = docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | Where-Object { $_ -like "${imageName}:$localTag *" } | ForEach-Object { $_.Split(' ')[1] }
            Write-Host "This is the old image: ${imageName}:$localTag"
            docker rmi "ghcr.io/$org/${imageName}:$localTag" -f
            Write-Host "Old image removed: ghcr.io/$org/${imageName}:$localTag"

            # Container creation based on latest image version
            if ($portMapping) {
                Write-Host "Successfully pulled the latest version: ${imageName}:$latestTag. Now starting a container with port mapping: $portMapping..."
                docker run -d --name "$imageName" -e HOSTNAME=$env:COMPUTERNAME -p $portMapping "ghcr.io/$org/${imageName}:$latestTag"
                if ($?) {
                    Write-Host "Successfully started the container: $imageName"
                } else {
                    Write-Host "Failed to start the container for $imageName"
                }
            } else {
                Write-Host "Failed to pull the latest version of $imageName"
            }
        }
    }
}
