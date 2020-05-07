>**NOTE** It looks like that the Extractor tool I have been using is not generating a master template file for the API. A master template would link all the individual templates together in the correct order of deployment. As a result, it looks like that this repo is instantly obsolete, I may look in to the issue and see if there is still a need for a updated version of this repo.

## Deploy API Management API's through an Azure DevOps Pipeline
This is a sample implementation of a Azure DevOps pipeline deployment for Azure API Management API's.

This repo continues on the work done in the [Azure API Management DevOps Resource Kit](https://github.com/Azure/azure-api-management-devops-resource-kit) repo. Specifically, this repo focusses on the deploying the extracted API's in a repeatable way through an Azure DevOps Pipeline.

## The challenges
Once the API(s) have been extracted from API Management, you have a nice collection of ARM templates which can be maintained through a DevOps process and deployed to various API Management instances.

When asked by customers about how to manage the API's within API Management in a DevOps process they are facing some or all of the following challenges:

* **ARM Templates** for most people are not the first choice when it comes to Azure resource deployments, resulting in the creation of many custom scripts which are, most often, not reusable.
* **Policies embedded in ARM** are impossible to maintain, extracting the policies to linked XML Files require a storage account during ARM deployments.
* **One repo per API or one for many** is often a question not easily answered. Most of the concerns and objections for each are around security, control, deployment duration, deployment of API's not changed etc.
* **Manage API's at Scale** and you'll find that custom scripts and pipelines are impossible to manage and maintain.   

## A Principled Approach
I am not pretending this is THE solution or THE recommended way of doing things. This repo only offers an approach based on some principles I use when discussing software development in general and in this case deployment of API's in a DevOps process.

No, these are not all the principles you can or should apply, these are just the ones I used to create something you can use in your day-to-day operation.

* **KISS**, Keep It Stupidly Simple is one of my favorits. The approach should be simple enough to understand, deploy, maintain, improve and expand upon. 
* **Common Practices** without the use of hacks.
* **Configuration over Scripting** to get going with the approach. 
* **Leverage the Resource Kit** as a consistent method for generating structured ARM Templates ready for redeployment.
* **External Policy Files** to allow for maintenance and development outside of the ARM templates.
* **Deploy ARM Templates** from the Resource Kit Extractor tool without any changes.

## Parts of the Solution
The solution consists of three main parts:
* **The Resource Kit Extractor tool**, which is not really part of this solution but this solution is based on how the tool extracts an API and the ARM Templates it generates. 
* **An Azure DevOps Pipeline** sample structure has been created which allows for individual and mass deployment of the API's present within a repo. The sample pipeline structure also introduces a bit of modularity and parametarization to support the need to only change configuration rather that change structures.
* **A PowerShell Deployment Task** to deploy the ARM Templates making up the API within API Management. This PowerShell script takes care of copying linked files to a Blob Storage account and deploys the ARM Templates.

## Known Limitations
As this approach is a work in progress the limitations are mostly within the current capabilites of the PowerShell deployment task recognizing the settings used during API extraction using the Extractor tool.
  
## License
This project is licensed under the MIT License.

## Contributing
This project welcomes contributions and suggestions. 
