## The Resources Folder
In this folder you find a **modules** and a **pipeline** folder, a **DeployAPI.ps1** PowerShell script, and a **azure-pipelines.yml** ADO master pipeline file.

### Modules Folder
This folder is intended to contain ADO pipeline templates which are reused within the pipelines for each of the API's you maintain. The **pipeline.deploy.yaml** is the first of the modular templates which uses the DeployAPI.ps1 script to deploy the ARM templates of an API. There are other example module files such as **pipeline.validate.yaml** and **pipeline.build.yaml** in there as well. *These last two files are currently not functional.*

### Pipeline Folder
This folder contains three yaml files which, as a folder, need to be copied into each API folder created by the Extractor tool.

### DeployAPI.ps1 PowerShell script
This script is used as a task within the pipeline.deploy.yaml file. In handles the deployment of each and every ARM template created by the Extractor tool.

It checks whether there are policy XML files present and if so, it will copy these XML files to blob storage so the ARM deployment process can reach them.

This scipt will create a storage container called "policies" if it doesn't exists already in your storage account. This container is set to "private", and the process will create a SAS token for the container with a default duration of 30 minutes. It will copy the policy files into this container at the start of the deployment process and remove them at the end.

### azure-pipelines.yml
This is a sample Master Pipeline which can be used to deploy all individual API's together as part of a disaster recovery or a regional change over exercise.

***Note:** Currently not included, sample will come soon.*

## How to Get Started
### 1. Copy Files to Repo
First copy the **DeployAPI.ps1** and the **azure-pipelines.yml** files to the root of your repo.

### 2. Copy Modules Folder to Repo
Copy the **Modules** folder to the root of your repo.

### 3. Copy your API Folder to REpo
Copy the whole folder of the API you extracted using the Extract tool to the root of your repo. If you have multiple API folders, copy them all into the root as well.

### 4. Copy the Pipeline Folder in API Folder
Copy the pipeline folder in each of the API folders you have added to your repo. 

*The pipeline folder contains the pipeline files which are unique to your API. These pipeline files will use the reusable template files in the Modules folder. This allows you to easily adust environmental settings and deployment steps for each API while still leveraging tasks and steps common among all.*

The final Repo structure should look like this
```
Repo Root
+- Modules
|  +- pipeline.build.yaml
|  +- pipeline.deploy.yaml
|  +- pipeline.validate.yaml
|
+- DeployAPI.ps1
+- azure-pipelines.yml
|
+- {Your API Folder}
|  +- pipeline
|  |  +- pipeline.environments.yaml
|  |  +- pipeline.variables.yaml
|  |  +- pipeline.yaml
|  |
|  +- policies
|  |  +- { policy XML files }
|  |
|  +- { API ARM Template files }
|
+- {Your Other API Folder}
|  +- pipeline
|  +- policies
|  +- { API ARM Template files }

```
### 5a. Change the Pipeline Files
Open the **pipeline.yaml** file for one of your API's and change the trigger path to match the folder name of your API.

In the example below, change the section "{ Your API Folder name }" to the name of the folder where this API is located in.

*This will prevent this pipeline to be triggered by files changed in other API folders and only execute this pipeline when a change in your api folder has changed.*

```
trigger:
    branches:
      include:
      - develop
      - staging
      - release
      - master
    paths:
      exclude:
        - ./*
      include:
      - { Your API Folder name }/*
```

### 5b. Change the Pipeline Variables Files
The pipeline.variables.yaml file contains all the global variables for the pipeline. You can add more parameters if you want.

Open the **pipeline.variables.yaml** file and change the **apiName** variable in the file to match the API name as it was named in API Management.

### 5c. Change the Pipeline Environments Files
The pipeline.environments.yaml file contains Stage or Job specific variables. In this solution the environments file is use at the Stage level and is controled by a **paramSet** parameter which indicates which set of variables to use. You can add more variables in this file once you start expanding your stages. The variables mentioned below are required for this process to function properly.

Open the **pipeline.environments.yaml** file and change the following variables for each of the environments you want to deploy the API to.
* **azureSubscription** contains the Service Connection string/name you can find in Azure DevOps under **Project Settings** -> **Pipelines** --> **Service Connections**

* **storageAccountName** contains the name of the Azure Storage Account which is used to copy the policy XML files to during deployment. This storage account should be within the same Azure Subscription containing the target API Management instance.

* **apiManagementInstanceName** contains the API Management Instance name. This API Management instance should be present in the Azure Subscription you have specified in the azureSubscription variable.

* **enviro** contains a environment indentification which is used as a postfix for the ARM template parameters file of your API.

The Extractor tool generates a default parameters.json file containing the required parameters needed for deploying the ARM Templates. Most of these parameters do not need to be changed as the deployment process will automatically override these parameters.
However, if you choose to further enhance the ARM Templates with additional variables, you can do so for each environment you want to deploy to by cloning the parameters file.

if you leave the enviro variable blank ('') the process will then use the default parameters.json file. If you set it to 'dev' for example, the process will then look for and use a parameters-dev.json file, similarly if you would set the enviro variable to 'qa' or 'prod' it would look for and use the parameters-qa.json or parameters-prod.json file respectively.

### 6. Import API Pipeline in ADO
In the Azure DevOps pipeline section, import the pipeline.yaml file for each of the API folders you have added to the repo.
