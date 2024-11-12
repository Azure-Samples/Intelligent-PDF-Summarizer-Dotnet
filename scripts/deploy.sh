#!/bin/bash


commands=("azd" "az" "func" "dotnet")

for cmd in "${commands[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd command is not available, check pre-requisites in README.md"
    exit 1
  fi
done

# delete the bin and obj folders to get around an issue - temporary, fix is coming
rm -rf ./bin
rm -rf ./obj

# Define variables
functionAppPath="."
zipFilePath="./bin/publish"
zipFileName="functions.zip"

# Create the the application zip package
azd package --output-path $zipFilePath/$zipFileName

# Fetch Azure environment variables using azd env get-values
output=$(azd env get-values)

# Use a file descriptor to avoid subshell
while IFS= read -r line; do
  name=$(echo "$line" | cut -d'=' -f1 | sed 's/^["'\'']//;s/["'\'']$//')
  value=$(echo "$line" | cut -d'=' -f2 | sed 's/^["'\'']//;s/["'\'']$//')
  export "$name=$value"
  echo "$name=$value"
done <<< "$output"

echo ""
echo "Environment variables set."
echo ""
# echo "Showing environment variables with env command:"
# env

# Upload the zip package to Azure Storage Blob container
echo "Uploading functions.zip to Azure Storage Blob container $AZURE_STORAGE_ACCOUNT_NAME/$AZURE_STORAGE_CONTAINER_NAME/$zipFileName..."
echo "az storage blob upload --account-name $AZURE_STORAGE_ACCOUNT_NAME --container-name $AZURE_STORAGE_CONTAINER_NAME --name $zipFileName --file $zipFilePath/$zipFileName --auth-mode login --overwrite"
az storage blob upload --account-name $AZURE_STORAGE_ACCOUNT_NAME --container-name $AZURE_STORAGE_CONTAINER_NAME --name $zipFileName --file $zipFilePath/$zipFileName --auth-mode login --overwrite

echo "Deployed functions.zip successfully to $AZURE_STORAGE_ACCOUNT_NAME/$AZURE_STORAGE_CONTAINER_NAME/$zipFileName"

# Restarting the function app with new functions.zip blob
echo "Restarting the function app..."
echo "az functionapp restart --name $AZURE_FUNCTION_NAME --resource-group $AZURE_RESOURCE_GROUP"
az functionapp restart --name $AZURE_FUNCTION_NAME --resource-group $AZURE_RESOURCE_GROUP

# Purge a deleted resource
# az resource delete --ids /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$AZURE_FORMRECOGNIZER_SERVICE
# az resource delete --ids /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$AZURE_SEARCH_SERVICE

# recover
# az cognitiveservices account recover --location $AZURE_LOCATION --name $AZURE_FORMRECOGNIZER_SERVICE --resource-group $AZURE_RESOURCE_GROUP