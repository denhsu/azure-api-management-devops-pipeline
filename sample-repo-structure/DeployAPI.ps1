<# 
	These next five variables need to be provided through the pipeline, 
	rather than hard coded in this script.
	The subscription context and authentication is done through
	the AzurePowershell task in the pipeline.
#>
[CmdletBinding()]
param
(
    # Storage Account Name
    [Parameter(Mandatory = $true)]
    [String] $SAName,

    # API Management Name
    [Parameter(Mandatory = $true)]
    [String] $APIMName,

    # API Name to deploy or "ALL"
    [Parameter(Mandatory = $true)]
    [String] $APIName,    
    
    # Environment (eg dev, uat, prod) 
    # if left as empty string, it uses the default *parameters.json file
    # it is not recommended to have multiple parameter files in
    # the folder but not specifying one specifically.
    [String] $Env
)

function GetDirectoriesToDeploy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$folderName
    )
    Write-Host "Retrieving API Folders to Deploy.." -NoNewline
    
    # Check if we are deploying one specific API or "ALL"
    if($folderName.ToLower() -eq "all")
    {
        $dirs = Get-ChildItem -Directory -Exclude .vscode
    }
    else {
        $dirs = Get-ChildItem -Directory -Filter $folderName
    }

    Write-Host "Ok." -ForegroundColor Green

    return $dirs
}

function BuildParametersFromTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$templateFile,
        [Parameter(Mandatory)]
        [object]$parameters
    )
    Write-Host "   - Building Parameter set: " -NoNewline
    # Get the ARM Template Loaded
    $params = (Get-Content $templateFile.Name | Out-String | ConvertFrom-Json).parameters
    
    $newParamSet = @{}
    
    # Build a new Parameter set with the parameter required by the template
    foreach($param in $($params).psobject.properties) {
        if($newParamSet.Count -gt 0) { 
            Write-Host ", " -NoNewline 
        }
        
        switch ($param.Value.type) {
            "string" {  
                $newParamSet.Add($param.Name, $($parameters).psobject.properties[$param.Name].value.value); 
                break
            }
            "object" {
                $collection = BuildHashTable $($parameters).psobject.properties[$param.Name].value

                $newParamSet.Add($param.Name, $collection )

                break 
            }
            Default {}
        }

        Write-Host "$($param.Name)" -NoNewline 
    }

    Write-Host "..Ok." -ForegroundColor Green

    return $newParamSet
}

function BuildHashTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$itemList
    )
    $result = @{}

    foreach($item in $($itemList).psobject.properties) {
        switch ($item.TypeNameOfValue) {
            "System.String" {  
                $result.Add($item.Name, $item.Value); 
                break
            }
            "System.Object" {
                $result.Add($item.Name, $null)
            }
            "System.Management.Automation.PSCustomObject" {
                $collection = BuildHashTable $($item).value

                if($item.Name -eq "value")
                { 
                    $result = $collection
                }
                else {
                    $result.Add($item.Name, $collection)
                }
                break 
            }
            Default {}
        }
    }

    return $result
}

function DeployToAzure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$folderName,
        [Parameter(Mandatory)]
        [string]$deploymentName,
        [Parameter(Mandatory)]
        [object]$templateFile,
        [Parameter(Mandatory)]
        [object]$parameters,
        [Parameter(Mandatory)]
        [string]$containerToken,
        [Parameter(Mandatory)]
        [object]$apimInstance
    )

    $paramSet = BuildParametersFromTemplate $templateFile $parameters


    Write-Host "   - Deploying API Template file: $($templateFile.Name)..." -NoNewline
    $result = New-AzResourceGroupDeployment `
    -mode incremental `
    -name "$($folderName)-$($deploymentName)" `
    -ResourceGRoupName $apimInstance.ResourceGroupName `
    -templatefile $templateFile.Name `
    -TemplateParameterObject $paramSet `
    -PolicyXMLBaseURL "https://$($SAName).blob.core.windows.net/$($containerName)/$($folderName)" `
    -PolicyXMLSasToken $containerToken `
    -ApimServiceName $apimInstance.Name 

    if($result.ProvisioningState -eq "Succeeded") {
        Write-Host $result.ProvisioningState -ForegroundColor Green
    }
    else {
        Write-Host $result -ForegroundColor Red   
    }
}

function GetAPIManagementInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$APIMInstanceName
    )

    Write-Host "Checking if API Management Instance '$($APIMInstanceName)' exists..." -NoNewline
    $result = Get-AzResource -Name $APIMInstanceName

    if($null -eq $result) {
        Write-Host "Not Found, Deployment Cancelled" -ForegroundColor Red   
    }
    else {
        Write-Host "Ok." -ForegroundColor Green
    }

    return $result
}

function GetStorageAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SAName
    )

    Write-Host "Checking if StorageAccount '$($SAName)' exists..." -NoNewline
    $result = Get-AzResource -Name $SAName

    if($null -eq $result) {
        Write-Host "Not Found, Deployment Cancelled" -ForegroundColor Red   
    }
    else {
        Write-Host "Ok." -ForegroundColor Green
    }

    Write-Host "Connecting to the Storage account..." -NoNewline

    $result = Get-AzStorageAccount `
        -ResourceGroupName $result.ResourceGroupName `
        -AccountName $SAName

    Write-Host "Ok." -ForegroundColor Green

    return $result
}

function GetParametersFile {
    [CmdletBinding()]
    param(
        [string]$Enviro
    )
    
    Write-Host "-  Locating Parameters file..." -NoNewline
    if( $Enviro -eq '') {
           $result = Get-ChildItem $("*parameters.json")  
    } else {
        $result = Get-ChildItem $("*parameters-$Env.json")  
    }

    if($null -eq $result) {
        Write-Host "Not Found, Deployment Cancelled" -ForegroundColor Red
    }else {
        Write-Host "Ok." -ForegroundColor Green
        $result = (Get-Content $result.Name | Out-String | ConvertFrom-Json).parameters
    }

    return $result 
}

function GenerateSASToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$storageAccount
    )

    Write-Host "Generating Container SAS-Token..." -NoNewline
    $storageContext = New-AzStorageContext -ConnectionString $storageAccount.Context.ConnectionString

    # Does the "policies" container exists
    $result = Get-AzStorageContainer -Name $containerName -Context $storageContext
    if($null -eq $result)
    {
        # Create a new storage container
        $result = New-AzStorageContainer -Context $storageContext -Name $containerName -Permission Off
    }

    # Get the SAS token for the container, Read only
    $result = New-AzStorageContainerSASToken `
        -Name $containerName `
        -Permission "r" `
        -Context $storageContext `
        -ExpiryTime $dateTime.AddMinutes($sasTokenLifeTime)
    
    if($null -ne $result) {
        Write-Host "Ok." -ForegroundColor Green  
    }else {
        Write-Host "Unable to retrieve SAS token, Deployment Cancelled" -ForegroundColor Red   
    }
 
    return $result
}

function CopyPolicyFilesToBlob {
    [CmdletBinding()]
    param(
        # API Folder
        [Parameter(Mandatory)]
        [object] $folder,        
        # Storage Account Object
        [Parameter(Mandatory)]
        [object] $storageAccount,
        # The Blob Storage Container where the files are located
        [Parameter(Mandatory)]
        [string] $containerName
    )

    Write-Host "-  Checking presence of Policy Files..." -NoNewline
    if(Test-Path Policies -PathType Container)
    {
        Write-Host "Ok." -ForegroundColor Green
        Write-Host "-  Retrieving the Policy Files..." -NoNewline
        $files = Get-ChildItem -Path .\policies -Include *Policy.xml -Recurse
        Write-Host "Ok." -ForegroundColor Green

        Write-Host "-  Copying policy file to Blob Storage..." -NoNewline
        foreach($file in $files) {
            $result = Set-AzStorageBlobContent -File  ".\policies\$($file.Name)" `
                -Container $containerName `
                -Blob "$($folder)/$($file.Name)" `
                -Context $storageAccount.Context `
                -Force
        }
        Write-Host "Ok." -ForegroundColor Green  
    }
    else {
        Write-Host "Not Found, Skipped for deployment." -ForegroundColor Blue 
    }

    return $Files
}
function RemovePolicyFilesFromBlob {
    [CmdletBinding()]
    param(
        # API Folder
        [Parameter(Mandatory)]
        [object] $folder, 
        # Storage Account Object
        [Parameter(Mandatory)]
        [object] $storageAccount,
        # The Blob Storage Container where the files are located
        [Parameter(Mandatory)]
        [string] $containerName,
         # List of Files to Remove from the Blob Container
        [Parameter(Mandatory)]
        [object] $files
    )

    Write-Host "-  Removing Policy file from Blob Storage..." -NoNewline
    foreach($file in $files) {
        Remove-AzStorageBlob `
        -Container $containerName `
        -Context $storageAccount.Context `
        -Blob "$($folder)/$($file.Name)" `
        -Force
    }
    Write-Host "Ok." -ForegroundColor Green
}

$sasTokenLifeTime = 30          # Life time of the Storage container SAS Token in minutes
$containerName = "policies"     # The Storage container name
$deploymentItems = "tags", "loggers", "products", "namedValues", "authorizationServers","apiversionsets","globalServicePolicy", "backends", "folder"
#$deploymentItems =  "folder"
$dateTime = Get-Date

$apimInstance = GetAPIManagementInstance $APIMName
if($null -eq $apimInstance) {  Exit-PSSession } 

$storageAccount = GetStorageAccount $SAName
if($null -eq $apimInstance) {  Exit-PSSession }

$storageToken = GenerateSASToken $storageAccount
if($null -eq $apimInstance) {  Exit-PSSession }

$directories = GetDirectoriesToDeploy($APIName)

foreach($apiFolder in $directories)
{
    Write-Host
    Write-Host "Deploying API '$apiFolder'"
    set-location $apiFolder.Name

    $policyFiles = CopyPolicyFilesToBlob $apiFolder.Name $storageAccount $containerName

    $apiParameters = GetParametersFile $Env
    if($null -eq $apiParameters) {  Exit-PSSession }

    # Deploying templates
    foreach($template in $deploymentItems) {
        if($template -eq "folder") { 
            Write-Host "-  Locating the API template file..." -NoNewline
            $template = $apiFolder.Name 
            $templateFile = Get-ChildItem $("*" + $apiFolder.Name + "*") -include *-api.template.json  -Recurse
        }
        else {
            Write-Host $("-  Locating $template file...") -NoNewline
            $templateFile = Get-ChildItem $("*$template.template.json")            
        }

        if($null -ne $templateFile)
        { 
            Write-Host "Ok." -ForegroundColor Green
          
            DeployToAzure $apiFolder.Name $template $templateFile $apiParameters $storageToken $apimInstance
        }
        else
        {
            Write-Host "Not Found, Skipped for deployment." -ForegroundColor Blue
        }
    }
 
    Set-Location ..

    RemovePolicyFilesFromBlob $apiFolder.Name $storageAccount $containerName $policyFiles
}