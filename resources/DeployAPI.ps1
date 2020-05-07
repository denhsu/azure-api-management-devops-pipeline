<# 
	These next five variables need to be provided through the pipeline, 
	rather than hard coded in this script.
	The subscription context and authentication is done through
	the AzurePowershell task in the pipeline.
#>
[CmdletBinding()]
param
(
    # Deployment Type
    [Parameter(Mandatory=$true)]
    [String] $Deploy,

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
        [string]$apiName
    )
    Write-Host "Retrieving API Folders to Deploy.." -NoNewline

    # Get Current Directory
    $loc = Get-Location
    
    # Check if we are deploying one specific API or "ALL"
    if($apiName.ToLower() -eq "all")
    {
        $dirs = Get-ChildItem -Directory -Exclude .vscode
        $dirs = $dirs.Name
  
        Write-Host "Ok." -ForegroundColor Green
    }
    else {
        $files = GET-ChildItem -include "*-$($apiName)-api.template.json", "*$($apiName);rev=*-api.template.json" -recurse
        if($null -ne $files)
        {
            $dirs = @()
            $selectedDirs = $files.VersionInfo.FileName.SubString($loc.Path.Length + 1)
            
            foreach($directory in $selectedDirs) 
            {
                $dirs += $directory.split('\')[0]
            }

            $dirs = $dirs | Select-Object -Unique
            
            Write-Host "Ok." -ForegroundColor Green
        }
        else {
            $dirs = $null 
            Write-Host "API not found, Canceling deployment." -ForegroundColor Red
        }
    }

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

    if($Deploy -eq "master")
    {
        $paramSet["LinkedTemplatesBaseUrl"] = "https://$($SAName).blob.core.windows.net/$($containerName)/$($folderName)"
        $paramSet["LinkedTemplatesSasToken"] = $containerToken
    }

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
            if($null -eq $result) {
                Write-Host "x" -ForgroundColor Red -NoNewLine
            }
            else
            {
                Write-Host "." -NoNewLine
            }
        }
        Write-Host "Ok." -ForegroundColor Green  
    }
    else {
        Write-Host "Not Found, Skipped for deployment." -ForegroundColor Blue 
    }

    return $Files
}

function CopyTemplateFilesToBlob {
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

    Write-Host "-  Retrieving the Template Files..." -NoNewline
    $files = Get-ChildItem *.template.json -exclude *master.template.json
    Write-Host "Ok." -ForegroundColor Green

    Write-Host "-  Copying Template files to Blob Storage..." -NoNewline
    foreach($file in $files) {
        $result = Set-AzStorageBlobContent -File  ".\$($file.Name)" `
            -Container $containerName `
            -Blob "$($folder)/$($file.Name)" `
            -Context $storageAccount.Context `
            -Force
        if($null -eq $result) {
            Write-Host "x" -ForgroundColor Red -NoNewLine
        }
        else
        {
            Write-Host "." -NoNewLine
        }
    }
    Write-Host "Ok." -ForegroundColor Green  

    return $Files
}

function RemoveFilesFromBlob {
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

    foreach($file in $files) {
        Remove-AzStorageBlob `
        -Container $containerName `
        -Context $storageAccount.Context `
        -Blob "$($folder)/$($file.Name)" `
        -Force
    }
    Write-Host "Ok." -ForegroundColor Green
}

function IsRevisionMasterFolderPresent {
    $result = Get-ChildItem -Directory -filter RevisionMasterFolder

    if( $null -ne $result)
    {
        return $true
    }
    else {
        return $false
    }
}

function ValidateParameters {
    if($Deploy -notin @("master", "api", "instance"))
    {
        Write-Host "Missing or incorrect Deploy parameter value: The valid values for the 'Deploy' parameter are: master, api, instance" -ForegroundColor Red
        Exit
    }

    if($null -eq $APIMName)
    {
        Write-Host "Missing or incorrect APIMName parameter value: The 'APMName' parameter requires the name of an existing API Management Instance" -ForegroundColor Red
        Exit  
    }

    if($null -eq $SAName)
    {
        Write-Host "Missing or incorrect SAName parameter value: The 'SAName' parameter requires the name of an existing Azure Storage Account" -ForegroundColor Red
        Exit  
    }

    if($null -eq $APIName -and $APIName.ToLower() -ne "all")
    {
        Write-Host "Missing or incorrect APIName parameter value: The 'APIName' parameter requires the name of an api folder or 'all'" -ForegroundColor Red
        Exit  
    }
}

function GetDeploymentItems {
    if($Deploy.ToLower() -eq "instance")
    {   
        return "tags", "loggers", "products", "namedValues", "authorizationServers","globalServicePolicy"
    } 
    elseif ($Deploy.ToLower() -eq "api") {
        return "apiversionsets", "backends", "api"
    }
    else {
        return $Deploy.ToLower()
    }
}

$sasTokenLifeTime = 30          # Life time of the Storage container SAS Token in minutes
$containerName = "policies"     # The Storage container name
$dateTime = Get-Date

# Check whether all parameters are provided
ValidateParameters

$apimInstance = GetAPIManagementInstance $APIMName
if($null -eq $apimInstance) {  Exit } 

$storageAccount = GetStorageAccount $SAName
if($null -eq $apimInstance) {  Exit }

$storageToken = GenerateSASToken $storageAccount
if($null -eq $apimInstance) {  Exit }

$directories = GetDirectoriesToDeploy($APIName)
$inRevisionFolder = $false

foreach($apiFolder in $directories)
{
    Write-Host
    Write-Host "Deploying API in folder '$apiFolder'"
    set-location $apiFolder

    ## if there is a Master revision folder
    ## we'll make the master folder the focus.
    if(IsRevisionMasterFolderPresent -eq $true)
    {
        set-location 'RevisionMasterFolder'
        $inRevisionFolder = $true
    }
    else 
    {
        $inRevisionFolder = $false
    }

    # What do we need to copy
    # if the Deployment is set to master, we need to copy arm templates and policies
    # if the Deployment is set to api we only need to copy the policies
    # if the Deployment is set to instance we only need to copy the policies
    $policyFiles = CopyPolicyFilesToBlob $apiFolder $storageAccount $containerName

    if($Deploy -eq "master") {
        $templateFiles = CopyTemplateFilesToBlob $apiFolder $storageAccount $containerName
    }

    $apiParameters = GetParametersFile $Env
    if($null -eq $apiParameters) {  Exit }

    # Deploying templates
    foreach($template in GetDeploymentItems) {
        if($template -eq "api") { 
            Write-Host "-  Locating the API template file..." -NoNewline
            $template = $apiFolder
            $templateFile = Get-ChildItem * -include "*-api.template.json", "*-apis.template.json"
        }
        elseif ($template -eq "master") {
            Write-Host "-  Locating the Master template file..." -NoNewline
            $template = $apiFolder
            $templateFile = Get-ChildItem * -include "*master.template.json"
        }
        else {
            Write-Host $("-  Locating $template file...") -NoNewline
            $templateFile = Get-ChildItem $("*$template.template.json")            
        }

        if($null -ne $templateFile)
        { 
            Write-Host "Ok." -ForegroundColor Green
          
            DeployToAzure $apiFolder $template $templateFile $apiParameters $storageToken $apimInstance
        }
        else
        {
            Write-Host "Not Found, Skipped for deployment." -ForegroundColor Blue
        }
    }
 
    if($inRevisionFolder -eq $true)
    {
        # Backup to the main API folder
        Set-Location ..
    }

    Set-Location ..

    Write-Host "-  Removing Policy files from Blob Storage..." -NoNewline
    RemoveFilesFromBlob $apiFolder $storageAccount $containerName $policyFiles

    if($Deploy.ToLower() -eq "master")
    {
        Write-Host "-  Removing Template files from Blob Storage..." -NoNewline
        RemoveFilesFromBlob $apiFolder $storageAccount $containerName $templateFiles
    }
}