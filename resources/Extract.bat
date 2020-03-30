@echo OFF

SET ToolPath=C:\Data\Projects\APIM DevOps Kit\azure-api-management-devops-resource-kit\src\APIM_ARMTemplate\apimtemplate\bin\Release\netcoreapp3.1

IF "%ToolPath%" == "" GOTO :ToolPathMissing
IF "%~1" == "" GOTO :ParamNotProvided

GOTO :ExistsFunction

:ParamNotProvided
echo ERROR: The parameter file name is missing.
echo        The correct use of this batch file is:
echo        CREATE {parameters}.json
echo.
echo        A sample of the content of a parameter file can be found at:
echo        https://github.com/Azure/azure-api-management-devops-resource-kit/blob/master/src/APIM_ARMTemplate/README.md#running-the-extractor
GOTO ExitFunction

:ToolPathMissing
echo ERROR: The ToolPath variable is not set.
echo        Please set the ToolPath variable in this file to the 
echo        folder where the API Management DevOps ToolKit is located.
echo        You can download the API Management DevOps ToolKit at:
echo        https://github.com/Azure/azure-api-management-devops-resource-kit/releases
GOTO ExitFunction

:ExistsFunction
echo.
echo Please wait..
"%ToolPath%\apimtemplate" extract --extractorConfig %~1.json 
echo Your API has been extracted and placed in a folder named "%~1"
echo.
GOTO ExitFunction

:ExitFunction