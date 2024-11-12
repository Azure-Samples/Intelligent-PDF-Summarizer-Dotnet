#!/usr/bin/env pwsh

# Check if required commands are available
$commands = @("azd", "az", "func", "dotnet")

foreach ($cmd in $commands) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "Error: $cmd command is not available, check pre-requisites in README.md"
        exit 1
    }
}

# Delete the bin and obj folders to get around an issue - temporary, fix is coming
Remove-Item -Recurse -Force ./bin, ./obj

# Define variables
$functionAppPath = "."
$zipFilePath = "./bin/publish"
$zipFileName = "functions.zip"

# Create the application zip package
azd package --output-path "$zipFilePath/$zipFileName"

# Fetch Azure environment variables using azd env get-values
$output = azd env get-values

# Use a loop to set environment variables
$output -split "`n" | ForEach-Object {
    $line = $_.Trim()
    if ($line) {
        $name, $value = $line -split '=', 2
        $name = $name.Trim('"')
        $value = $value.Trim('"')
        [System.Environment]::SetEnvironmentVariable($name, $value)
        Write-Output "$name=$value"
    }
}

Write-Output ""
Write-Output "Environment variables set."
Write-Output ""

# Upload the zip package to Azure Storage Blob container
Write-Output "Uploading functions.zip to Azure Storage Blob container $env:AZURE_STORAGE_ACCOUNT_NAME/$env:AZURE_STORAGE_CONTAINER_NAME/$zipFileName..."
az storage blob upload --account-name $env:AZURE_STORAGE_ACCOUNT_NAME --container-name $env:AZURE_STORAGE_CONTAINER_NAME --name $zipFileName --file "$zipFilePath/$zipFileName" --auth-mode login --overwrite

Write-Output "Deployed functions.zip successfully to $env:AZURE_STORAGE_ACCOUNT_NAME/$env:AZURE_STORAGE_CONTAINER_NAME/$zipFileName"

# Restarting the function app with new functions.zip blob
Write-Output "Restarting the function app..."
az functionapp restart --name $env:AZURE_FUNCTION_NAME --resource-group $env:AZURE_RESOURCE_GROUP

# Purge a deleted resource (commented out)
# az resource delete --ids /subscriptions/$env:AZURE_SUBSCRIPTION_ID/resourceGroups/$env:AZURE_RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$env:AZURE_FORMRECOGNIZER_SERVICE
# az resource delete --ids /subscriptions/$env:AZURE_SUBSCRIPTION_ID/resourceGroups/$env:AZURE_RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$env:AZURE_SEARCH_SERVICE

# Recover (commented out)
# az cognitiveservices account recover --location $env:AZURE_LOCATION --name $env:AZURE_FORMRECOGNIZER_SERVICE --resource-group $env:AZURE_RESOURCE_GROUP