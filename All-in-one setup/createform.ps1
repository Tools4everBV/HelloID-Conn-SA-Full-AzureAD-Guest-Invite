# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
#Note: when running this script inside HelloID; portalUrl and API credentials are provided automatically (generate and save API credentials first in your admin panel!)
$portalUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$delegatedFormAccessGroupNames = @("") #Only unique names are supported. Groups must exist!
$delegatedFormCategories = @("User Management","Entra ID") #Only unique names are supported. Categories will be created if not exists
$script:debugLogging = $false #Default value: $false. If $true, the HelloID resource GUIDs will be shown in the logging
$script:duplicateForm = $false #Default value: $false. If $true, the HelloID resource names will be changed to import a duplicate Form
$script:duplicateFormSuffix = "_tmp" #the suffix will be added to all HelloID resource names to generate a duplicate form with different resource names

#The following HelloID Global variables are used by this form. No existing HelloID global variables will be overriden only new ones are created.
#NOTE: You can also update the HelloID Global variable values afterwards in the HelloID Admin Portal: https://<CUSTOMER>.helloid.com/admin/variablelibrary
$globalHelloIDVariables = [System.Collections.Generic.List[object]]@();

#Global variable #1 >> EntraIdCertificatePassword
$tmpName = @'
EntraIdCertificatePassword
'@ 
$tmpValue = @'

'@
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #2 >> EntraIdAppId
$tmpName = @'
EntraIdAppId
'@ 
$tmpValue = @'

'@
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #3 >> EntraIdTenantId
$tmpName = @'
EntraIdTenantId
'@ 
$tmpValue = @'

'@
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #4 >> EntraIdCertificateBase64String
$tmpName = @'
EntraIdCertificateBase64String
'@ 
$tmpValue = @'

'@
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #5 >> companyName
$tmpName = @'
companyName
'@ 
$tmpValue = @'

'@
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});


#make sure write-information logging is visual
$InformationPreference = "continue"

# Check for prefilled API Authorization header
if (-not [string]::IsNullOrEmpty($portalApiBasic)) {
    $script:headers = @{"authorization" = $portalApiBasic}
    Write-Information "Using prefilled API credentials"
} else {
    # Create authorization headers with HelloID API key
    $pair = "$apiKey" + ":" + "$apiSecret"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $key = "Basic $base64"
    $script:headers = @{"authorization" = $Key}
    Write-Information "Using manual API credentials"
}

# Check for prefilled PortalBaseURL
if (-not [string]::IsNullOrEmpty($portalBaseUrl)) {
    $script:PortalBaseUrl = $portalBaseUrl
    Write-Information "Using prefilled PortalURL: $script:PortalBaseUrl"
} else {
    $script:PortalBaseUrl = $portalUrl
    Write-Information "Using manual PortalURL: $script:PortalBaseUrl"
}

# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"  

# Make sure to reveive an empty array using PowerShell Core
function ConvertFrom-Json-WithEmptyArray([string]$jsonString) {
    # Running in PowerShell Core?
    if($IsCoreCLR -eq $true){
        $r = [Object[]]($jsonString | ConvertFrom-Json -NoEnumerate)
        return ,$r  # Force return value to be an array using a comma
    } else {
        $r = [Object[]]($jsonString | ConvertFrom-Json)
        return ,$r  # Force return value to be an array using a comma
    }
}

function Invoke-HelloIDGlobalVariable {
    param(
        [parameter(Mandatory)][String]$Name,
        [parameter(Mandatory)][String][AllowEmptyString()]$Value,
        [parameter(Mandatory)][String]$Secret
    )

    $Name = $Name + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automation/variables/named/$Name")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false

        if ([string]::IsNullOrEmpty($response.automationVariableGuid)) {
            #Create Variable
            $body = @{
                name     = $Name;
                value    = $Value;
                secret   = $Secret;
                ItemType = 0;
            }    
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/automation/variable")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $variableGuid = $response.automationVariableGuid

            Write-Information "Variable '$Name' created$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        } else {
            $variableGuid = $response.automationVariableGuid
            Write-Warning "Variable '$Name' already exists$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
    } catch {
        Write-Error "Variable '$Name', message: $_"
    }
}

function Invoke-HelloIDAutomationTask {
    param(
        [parameter(Mandatory)][String]$TaskName,
        [parameter(Mandatory)][String]$UseTemplate,
        [parameter(Mandatory)][String]$AutomationContainer,
        [parameter(Mandatory)][String][AllowEmptyString()]$Variables,
        [parameter(Mandatory)][String]$PowershellScript,
        [parameter()][String][AllowEmptyString()]$ObjectGuid,
        [parameter()][String][AllowEmptyString()]$ForceCreateTask,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $TaskName = $TaskName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/automationtasks?search=$TaskName&container=$AutomationContainer")
        $responseRaw = (Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false) 
        $response = $responseRaw | Where-Object -filter {$_.name -eq $TaskName}

        if([string]::IsNullOrEmpty($response.automationTaskGuid) -or $ForceCreateTask -eq $true) {
            #Create Task

            $body = @{
                name                = $TaskName;
                useTemplate         = $UseTemplate;
                powerShellScript    = $PowershellScript;
                automationContainer = $AutomationContainer;
                objectGuid          = $ObjectGuid;
                variables           = (ConvertFrom-Json-WithEmptyArray($Variables));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/automationtasks/powershell")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $taskGuid = $response.automationTaskGuid

            Write-Information "Powershell task '$TaskName' created$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        } else {
            #Get TaskGUID
            $taskGuid = $response.automationTaskGuid
            Write-Warning "Powershell task '$TaskName' already exists$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
    } catch {
        Write-Error "Powershell task '$TaskName', message: $_"
    }

    $returnObject.Value = $taskGuid
}

function Invoke-HelloIDDatasource {
    param(
        [parameter(Mandatory)][String]$DatasourceName,
        [parameter(Mandatory)][String]$DatasourceType,
        [parameter(Mandatory)][String][AllowEmptyString()]$DatasourceModel,
        [parameter()][String][AllowEmptyString()]$DatasourceStaticValue,
        [parameter()][String][AllowEmptyString()]$DatasourcePsScript,        
        [parameter()][String][AllowEmptyString()]$DatasourceInput,
        [parameter()][String][AllowEmptyString()]$AutomationTaskGuid,
        [parameter()][String][AllowEmptyString()]$DatasourceRunInCloud,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $DatasourceName = $DatasourceName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    $datasourceTypeName = switch($DatasourceType) { 
        "1" { "Native data source"; break} 
        "2" { "Static data source"; break} 
        "3" { "Task data source"; break} 
        "4" { "Powershell data source"; break}
    }

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/datasource/named/$DatasourceName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
    
        if([string]::IsNullOrEmpty($response.dataSourceGUID)) {
            #Create DataSource
            $body = @{
                name               = $DatasourceName;
                type               = $DatasourceType;
                model              = (ConvertFrom-Json-WithEmptyArray($DatasourceModel));
                automationTaskGUID = $AutomationTaskGuid;
                value              = (ConvertFrom-Json-WithEmptyArray($DatasourceStaticValue));
                script             = $DatasourcePsScript;
                input              = (ConvertFrom-Json-WithEmptyArray($DatasourceInput));
                runInCloud         = $DatasourceRunInCloud;
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl +"api/v1/datasource")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            
            $datasourceGuid = $response.dataSourceGUID
            Write-Information "$datasourceTypeName '$DatasourceName' created$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        } else {
            #Get DatasourceGUID
            $datasourceGuid = $response.dataSourceGUID
            Write-Warning "$datasourceTypeName '$DatasourceName' already exists$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
    } catch {
        Write-Error "$datasourceTypeName '$DatasourceName', message: $_"
    }

    $returnObject.Value = $datasourceGuid
}

function Invoke-HelloIDDynamicForm {
    param(
        [parameter(Mandatory)][String]$FormName,
        [parameter(Mandatory)][String]$FormSchema,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $FormName = $FormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/forms/$FormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }

        if(([string]::IsNullOrEmpty($response.dynamicFormGUID)) -or ($response.isUpdated -eq $true)) {
            #Create Dynamic form
            $body = @{
                Name       = $FormName;
                FormSchema = (ConvertFrom-Json-WithEmptyArray($FormSchema));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/forms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $formGuid = $response.dynamicFormGUID
            Write-Information "Dynamic form '$formName' created$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        } else {
            $formGuid = $response.dynamicFormGUID
            Write-Warning "Dynamic form '$FormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
    } catch {
        Write-Error "Dynamic form '$FormName', message: $_"
    }

    $returnObject.Value = $formGuid
}


function Invoke-HelloIDDelegatedForm {
    param(
        [parameter(Mandatory)][String]$DelegatedFormName,
        [parameter(Mandatory)][String]$DynamicFormGuid,
        [parameter()][Array][AllowEmptyString()]$AccessGroups,
        [parameter()][String][AllowEmptyString()]$Categories,
        [parameter(Mandatory)][String]$UseFaIcon,
        [parameter()][String][AllowEmptyString()]$FaIcon,
        [parameter()][String][AllowEmptyString()]$task,
        [parameter(Mandatory)][Ref]$returnObject
    )
    $delegatedFormCreated = $false
    $DelegatedFormName = $DelegatedFormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$DelegatedFormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }

        if([string]::IsNullOrEmpty($response.delegatedFormGUID)) {
            #Create DelegatedForm
            $body = @{
                name            = $DelegatedFormName;
                dynamicFormGUID = $DynamicFormGuid;
                isEnabled       = "True";
                useFaIcon       = $UseFaIcon;
                faIcon          = $FaIcon;
                task            = ConvertFrom-Json -inputObject $task;
            }
            if(-not[String]::IsNullOrEmpty($AccessGroups)) { 
                $body += @{
                    accessGroups    = (ConvertFrom-Json-WithEmptyArray($AccessGroups));
                }
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Information "Delegated form '$DelegatedFormName' created$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
            $delegatedFormCreated = $true

            $bodyCategories = $Categories
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$delegatedFormGuid/categories")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $bodyCategories
            Write-Information "Delegated form '$DelegatedFormName' updated with categories"
        } else {
            #Get delegatedFormGUID
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Warning "Delegated form '$DelegatedFormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
        }
    } catch {
        Write-Error "Delegated form '$DelegatedFormName', message: $_"
    }

    $returnObject.value.guid = $delegatedFormGuid
    $returnObject.value.created = $delegatedFormCreated
}

<# Begin: HelloID Global Variables #>
foreach ($item in $globalHelloIDVariables) {
	Invoke-HelloIDGlobalVariable -Name $item.name -Value $item.value -Secret $item.secret 
}
<# End: HelloID Global Variables #>


<# Begin: HelloID Data sources #>
<# Begin: DataSource "EntraID-Guest-Invite | Groups" #>
$tmpPsScript = @'
# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = 'SilentlyContinue'
$InformationPreference = "Continue"
$WarningPreference = "Continue"

function Get-MSEntraAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Certificate
    )
    try {
        # Get the DER encoded bytes of the certificate
        $derBytes = $Certificate.RawData

        # Compute the SHA-256 hash of the DER encoded bytes
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($derBytes)
        $base64Thumbprint = [System.Convert]::ToBase64String($hashBytes).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Create a JWT (JSON Web Token) header
        $header = @{
            'alg'      = 'RS256'
            'typ'      = 'JWT'
            'x5t#S256' = $base64Thumbprint
        } | ConvertTo-Json
        $base64Header = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header))

        # Calculate the Unix timestamp (seconds since 1970-01-01T00:00:00Z) for 'exp', 'nbf' and 'iat'
        $currentUnixTimestamp = [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime()).TotalSeconds)

        # Create a JWT payload
        $payload = [Ordered]@{
            'iss' = "$entraidappid"
            'sub' = "$entraidappid"
            'aud' = "https://login.microsoftonline.com/$EntraIdTenantId/oauth2/token"
            'exp' = ($currentUnixTimestamp + 3600) # Expires in 1 hour
            'nbf' = ($currentUnixTimestamp - 300) # Not before 5 minutes ago
            'iat' = $currentUnixTimestamp
            'jti' = [Guid]::NewGuid().ToString()
        } | ConvertTo-Json
        $base64Payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Extract the private key from the certificate
        $rsaPrivate = $Certificate.PrivateKey
        $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
        $rsa.ImportParameters($rsaPrivate.ExportParameters($true))

        # Sign the JWT
        $signatureInput = "$base64Header.$base64Payload"
        $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($signatureInput), 'SHA256')
        $base64Signature = [System.Convert]::ToBase64String($signature).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Create the JWT token
        $jwtToken = "$($base64Header).$($base64Payload).$($base64Signature)"

        $createEntraAccessTokenBody = @{
            grant_type            = 'client_credentials'
            client_id             = $entraidappid
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion      = $jwtToken
            resource              = 'https://graph.microsoft.com'
        }

        $createEntraAccessTokenSplatParams = @{
            Uri         = "https://login.microsoftonline.com/$EntraIdTenantId/oauth2/token"
            Body        = $createEntraAccessTokenBody
            Method      = 'POST'
            ContentType = 'application/x-www-form-urlencoded'
            Verbose     = $false
            ErrorAction = 'Stop'
        }

        $createEntraAccessTokenResponse = Invoke-RestMethod @createEntraAccessTokenSplatParams
        Write-Output $createEntraAccessTokenResponse.access_token
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-MSEntraCertificate {
    [CmdletBinding()]
    param()
    try {
        $rawCertificate = [system.convert]::FromBase64String($EntraIdCertificateBase64String)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $EntraIdCertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        Write-Output $certificate
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

function Resolve-MicrosoftGraphAPIErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        try {
            $errorObjectConverted = $ErrorObject | ConvertFrom-Json -ErrorAction Stop

            if ($null -ne $errorObjectConverted.error_description) {
                $errorMessage = $errorObjectConverted.error_description
            }
            elseif ($null -ne $errorObjectConverted.error) {
                if ($null -ne $errorObjectConverted.error.message) {
                    $errorMessage = $errorObjectConverted.error.message
                    if ($null -ne $errorObjectConverted.error.code) { 
                        $errorMessage = $errorMessage + " Error code: $($errorObjectConverted.error.code)"
                    }
                }
                else {
                    $errorMessage = $errorObjectConverted.error
                }
            }
            else {
                $errorMessage = $ErrorObject
            }
        }
        catch {
            $errorMessage = $ErrorObject
        }

        Write-Output $errorMessage
    }
}
#endregion functions

# Get Microsoft 365 Groups (Currently only Microsoft 365 and Security groups are supported by the Microsoft Graph API: https://docs.microsoft.com/en-us/graph/api/resources/groups-overview?view=graph-rest-1.0)
[System.Collections.ArrayList]$m365Groups = @()
try {
    try {
        # Setup Connection with Entra/Exo
        Write-Verbose 'connecting to MS-Entra'
        $certificate = Get-MSEntraCertificate
        $entraToken = Get-MSEntraAccessToken -Certificate $certificate
    
        #Add the authorization header to the request
        $authorization = @{
            Authorization = "Bearer $entraToken";
            'Content-Type' = "application/json";
            Accept = "application/json";
            'ConsistencyLevel' = 'eventual'
        } 
        # Define the properties to select (comma seperated)
        # Add optinal popertySelection (mandatory: id,displayName,onPremisesSyncEnabled)
        $properties = @("id", "displayName", "onPremisesSyncEnabled", "groupTypes")
        $select = "`$select=$($properties -join ",")"

        # Get Microsoft 365 Groups only (https://docs.microsoft.com/en-us/graph/api/group-list?view=graph-rest-1.0&tabs=http)
        Write-Verbose "Querying Microsoft 365 groups"

        $baseUri = "https://graph.microsoft.com/"
        $m365GroupFilter = "`$filter=groupTypes/any(c:c+eq+'Unified')"
        $splatWebRequest = @{
            Uri     = "$baseUri/v1.0/groups?$m365GroupFilter&$select&`$top=999&`$count=true"
            Headers = $authorization
            Method  = 'GET'
        }
        $getM365GroupsResponse = $null
        $getM365GroupsResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false
        foreach ($M365Group in $getM365GroupsResponse.value) { $null = $m365Groups.Add($M365Group) }
        
        while (![string]::IsNullOrEmpty($getM365GroupsResponse.'@odata.nextLink')) {
            $baseUri = "https://graph.microsoft.com/"
            $splatWebRequest = @{
                Uri     = $getM365GroupsResponse.'@odata.nextLink'
                Headers = $authorization
                Method  = 'GET'
            }
            $getM365GroupsResponse = $null
            $getM365GroupsResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false
            foreach ($M365Group in $getM365GroupsResponse.value) { $null = $m365Groups.Add($M365Group) }
        }

        Write-Information "Successfully queried Microsoft 365 groups. Result count: $($m365Groups.Count)"
    }
    catch {
        # Clean up error variables
        $verboseErrorMessage = $null
        $auditErrorMessage = $null

        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObject = Resolve-HTTPError -ErrorObject $ex

            $verboseErrorMessage = $errorObject.ErrorMessage

            $auditErrorMessage = Resolve-MicrosoftGraphAPIErrorMessage -ErrorObject $errorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
            $verboseErrorMessage = $ex.Exception.Message
        }
        if ([String]::IsNullOrEmpty($auditErrorMessage)) {
            $auditErrorMessage = $ex.Exception.Message
        }

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

        throw "Error querying Microsoft 365 Groups. Error Message: $auditErrorMessage"
    }
}
finally {
    # Send results
    $m365Groups | ForEach-Object {
        $returnObject = @{
            id   = $_.id
            name = $_.displayName
        }
        Write-Output $returnObject
    }
}

# Get Security Groups (Currently only Microsoft 365 and Security groups are supported by the Microsoft Graph API: https://docs.microsoft.com/en-us/graph/api/resources/groups-overview?view=graph-rest-1.0)
[System.Collections.ArrayList]$securityGroups = @()
try {
    try {
        # Setup Connection with Entra/Exo
        Write-Verbose 'connecting to MS-Entra'
        $certificate = Get-MSEntraCertificate
        $entraToken = Get-MSEntraAccessToken -Certificate $certificate
    
        #Add the authorization header to the request
        $authorization = @{
            Authorization = "Bearer $entraToken";
            'Content-Type' = "application/json";
            Accept = "application/json";
            'ConsistencyLevel' = 'eventual'
        } 

        # Define the properties to select (comma seperated)
        # Add optinal popertySelection (mandatory: id,displayName,onPremisesSyncEnabled)
        $properties = @("id", "displayName", "onPremisesSyncEnabled", "groupTypes")
        $select = "`$select=$($properties -join ",")"

        # Get Security Groups only (https://docs.microsoft.com/en-us/graph/api/resources/groups-overview?view=graph-rest-1.0)
        Write-Verbose "Querying Security groups"

        $securityGroupFilter = "`$filter=NOT(groupTypes/any(c:c+eq+'DynamicMembership')) and onPremisesSyncEnabled eq null and mailEnabled eq false and securityEnabled eq true"
        $baseUri = "https://graph.microsoft.com/"
        $splatWebRequest = @{
            Uri     = "$baseUri/v1.0/groups?$securityGroupFilter&$select&`$top=999&`$count=true"
            Headers = $authorization
            Method  = 'GET'
        }
        $getSecurityGroupsResponse = $null
        $getSecurityGroupsResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false
        foreach ($SecurityGroup in $getSecurityGroupsResponse.value) { $null = $securityGroups.Add($SecurityGroup) }
        
        while (![string]::IsNullOrEmpty($getSecurityGroupsResponse.'@odata.nextLink')) {
            $baseUri = "https://graph.microsoft.com/"
            $splatWebRequest = @{
                Uri     = $getSecurityGroupsResponse.'@odata.nextLink'
                Headers = $authorization
                Method  = 'GET'
            }
            $getSecurityGroupsResponse = $null
            $getSecurityGroupsResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false
            foreach ($SecurityGroup in $getSecurityGroupsResponse.value) { $null = $securityGroups.Add($SecurityGroup) }
        }

        Write-Information "Successfully queried Security groups. Result count: $($securityGroups.Count)"
    }
    catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObject = Resolve-HTTPError -ErrorObject $ex

            $verboseErrorMessage = $errorObject.ErrorMessage

            $auditErrorMessage = Resolve-MicrosoftGraphAPIErrorMessage -ErrorObject $errorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
            $verboseErrorMessage = $ex.Exception.Message
        }
        if ([String]::IsNullOrEmpty($auditErrorMessage)) {
            $auditErrorMessage = $ex.Exception.Message
        }

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

        throw "Error querying Security Groups. Error Message: $auditErrorMessage"
    }
}
finally {
    # Send results
    $securityGroups | ForEach-Object {
        $returnObject = @{
            id   = $_.id
            name = $_.displayName
        }
        Write-Output $returnObject
    }
}
'@ 
$tmpModel = @'
[{"key":"name","type":0},{"key":"id","type":0}]
'@ 
$tmpInput = @'
[]
'@ 
$dataSourceGuid_0 = [PSCustomObject]@{} 
$dataSourceGuid_0_Name = @'
EntraID-Guest-Invite | Groups
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_0_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "True" -returnObject ([Ref]$dataSourceGuid_0) 
<# End: DataSource "EntraID-Guest-Invite | Groups" #>
<# End: HelloID Data sources #>

<# Begin: Dynamic Form "EntraID Guest - Invite" #>
$tmpSchema = @"
[{"key":"email","templateOptions":{"label":"Email","placeholder":"user@domain.com","required":true},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"givenname","templateOptions":{"label":"Givenname","placeholder":"John","required":true,"minLength":2},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"lastname","templateOptions":{"label":"Last name","placeholder":"Poel","required":true,"minLength":2},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"messageArea","templateOptions":{"label":"Personal Message","rows":3},"className":"textarea-resize-vert","type":"textarea","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"groups","templateOptions":{"label":"Groups","useObjects":false,"useFilter":true,"options":["Option 1","Option 2","Option 3"],"useDataSource":true,"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_0","input":{"propertyInputs":[]}},"valueField":"name","textField":"name"},"type":"multiselect","summaryVisibility":"Show","textOrLabel":"text","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}]
"@ 

$dynamicFormGuid = [PSCustomObject]@{} 
$dynamicFormName = @'
EntraID Guest - Invite
'@ 
Invoke-HelloIDDynamicForm -FormName $dynamicFormName -FormSchema $tmpSchema  -returnObject ([Ref]$dynamicFormGuid) 
<# END: Dynamic Form #>

<# Begin: Delegated Form Access Groups and Categories #>
$delegatedFormAccessGroupGuids = @()
if(-not[String]::IsNullOrEmpty($delegatedFormAccessGroupNames)){
    foreach($group in $delegatedFormAccessGroupNames) {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/groups/$group")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
            $delegatedFormAccessGroupGuid = $response.groupGuid
            $delegatedFormAccessGroupGuids += $delegatedFormAccessGroupGuid
        
            Write-Information "HelloID (access)group '$group' successfully found$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormAccessGroupGuid })"
        } catch {
            Write-Error "HelloID (access)group '$group', message: $_"
        }
    }
    if($null -ne $delegatedFormAccessGroupGuids){
        $delegatedFormAccessGroupGuids = ($delegatedFormAccessGroupGuids | Select-Object -Unique | ConvertTo-Json -Depth 100 -Compress)
    }
}

$delegatedFormCategoryGuids = @()
foreach($category in $delegatedFormCategories) {
    try {
        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories/$category")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        $response = $response | Where-Object {$_.name.en -eq $category}
    
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid
    
        Write-Information "HelloID Delegated Form category '$category' successfully found$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    } catch {
        Write-Warning "HelloID Delegated Form category '$category' not found"
        $body = @{
            name = @{"en" = $category};
        }
        $body = ConvertTo-Json -InputObject $body -Depth 100

        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories")
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid

        Write-Information "HelloID Delegated Form category '$category' successfully created$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
}
$delegatedFormCategoryGuids = (ConvertTo-Json -InputObject $delegatedFormCategoryGuids -Depth 100 -Compress)
<# End: Delegated Form Access Groups and Categories #>

<# Begin: Delegated Form #>
$delegatedFormRef = [PSCustomObject]@{guid = $null; created = $null} 
$delegatedFormName = @'
Entra ID Guest - Invite
'@
$tmpTask = @'
{"name":"Entra ID Guest - Invite","script":"# Set TLS to accept TLS, TLS 1.1 and TLS 1.2\r\n[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12\r\n\r\n$VerbosePreference = 'SilentlyContinue'\r\n$InformationPreference = \"Continue\"\r\n$WarningPreference = \"Continue\"\r\n\r\n# variables configured in form\r\n#Change mapping here\r\n$invitation = [PSCustomObject]@{\r\n    invitedUserDisplayName  = $form.givenName + \" \" + $form.lastName;\r\n    invitedUserEmailAddress = $form.email;\r\n    sendInvitationMessage   = $true;\r\n    inviteRedirectUrl       = \"https://portal.azure.com/\";\r\n    invitedUserMessageInfo  = @{\r\n        customizedMessageBody = $form.messageArea # \"Personalized message body.\"\r\n        messageLanguage = \"nl-NL\" # If the customizedMessageBody is specified, this property is ignored, and the message is sent using the customizedMessageBody. The language format should be in ISO 639. The default is en-US.\r\n    }\r\n}\r\n\r\n$groupsToAdd = $form.groups\r\n\r\n# # Optional, fields to updated on account created from invitation\r\n# $updateAccount = @{\r\n#     CompanyName = $form.company\r\n#     Department  = $form.department\r\n#     jobTitle    = $form.title\r\n# }\r\n\r\n\r\n#region functions\r\nfunction Get-MSEntraAccessToken {\r\n    [CmdletBinding()]\r\n    param(\r\n        [Parameter(Mandatory)]\r\n        $Certificate\r\n    )\r\n    try {\r\n        # Get the DER encoded bytes of the certificate\r\n        $derBytes = $Certificate.RawData\r\n\r\n        # Compute the SHA-256 hash of the DER encoded bytes\r\n        $sha256 = [System.Security.Cryptography.SHA256]::Create()\r\n        $hashBytes = $sha256.ComputeHash($derBytes)\r\n        $base64Thumbprint = [System.Convert]::ToBase64String($hashBytes).Replace('+', '-').Replace('/', '_').Replace('=', '')\r\n\r\n        # Create a JWT (JSON Web Token) header\r\n        $header = @{\r\n            'alg'      = 'RS256'\r\n            'typ'      = 'JWT'\r\n            'x5t#S256' = $base64Thumbprint\r\n        } | ConvertTo-Json\r\n        $base64Header = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header))\r\n\r\n        # Calculate the Unix timestamp (seconds since 1970-01-01T00:00:00Z) for 'exp', 'nbf' and 'iat'\r\n        $currentUnixTimestamp = [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime()).TotalSeconds)\r\n\r\n        # Create a JWT payload\r\n        $payload = [Ordered]@{\r\n            'iss' = \"$entraidappid\"\r\n            'sub' = \"$entraidappid\"\r\n            'aud' = \"https://login.microsoftonline.com/$EntraIdTenantId/oauth2/token\"\r\n            'exp' = ($currentUnixTimestamp + 3600) # Expires in 1 hour\r\n            'nbf' = ($currentUnixTimestamp - 300) # Not before 5 minutes ago\r\n            'iat' = $currentUnixTimestamp\r\n            'jti' = [Guid]::NewGuid().ToString()\r\n        } | ConvertTo-Json\r\n        $base64Payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)).Replace('+', '-').Replace('/', '_').Replace('=', '')\r\n\r\n        # Extract the private key from the certificate\r\n        $rsaPrivate = $Certificate.PrivateKey\r\n        $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()\r\n        $rsa.ImportParameters($rsaPrivate.ExportParameters($true))\r\n\r\n        # Sign the JWT\r\n        $signatureInput = \"$base64Header.$base64Payload\"\r\n        $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($signatureInput), 'SHA256')\r\n        $base64Signature = [System.Convert]::ToBase64String($signature).Replace('+', '-').Replace('/', '_').Replace('=', '')\r\n\r\n        # Create the JWT token\r\n        $jwtToken = \"$($base64Header).$($base64Payload).$($base64Signature)\"\r\n\r\n        $createEntraAccessTokenBody = @{\r\n            grant_type            = 'client_credentials'\r\n            client_id             = $entraidappid\r\n            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'\r\n            client_assertion      = $jwtToken\r\n            resource              = 'https://graph.microsoft.com'\r\n        }\r\n\r\n        $createEntraAccessTokenSplatParams = @{\r\n            Uri         = \"https://login.microsoftonline.com/$EntraIdTenantId/oauth2/token\"\r\n            Body        = $createEntraAccessTokenBody\r\n            Method      = 'POST'\r\n            ContentType = 'application/x-www-form-urlencoded'\r\n            Verbose     = $false\r\n            ErrorAction = 'Stop'\r\n        }\r\n\r\n        $createEntraAccessTokenResponse = Invoke-RestMethod @createEntraAccessTokenSplatParams\r\n        Write-Output $createEntraAccessTokenResponse.access_token\r\n    }\r\n    catch {\r\n        $PSCmdlet.ThrowTerminatingError($_)\r\n    }\r\n}\r\n\r\nfunction Get-MSEntraCertificate {\r\n    [CmdletBinding()]\r\n    param()\r\n    try {\r\n        $rawCertificate = [system.convert]::FromBase64String($EntraIdCertificateBase64String)\r\n        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $EntraIdCertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)\r\n        Write-Output $certificate\r\n    }\r\n    catch {\r\n        $PSCmdlet.ThrowTerminatingError($_)\r\n    }\r\n}\r\n\r\nfunction Resolve-HTTPError {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Parameter(Mandatory,\r\n            ValueFromPipeline\r\n        )]\r\n        [object]$ErrorObject\r\n    )\r\n    process {\r\n        $httpErrorObj = [PSCustomObject]@{\r\n            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId\r\n            MyCommand             = $ErrorObject.InvocationInfo.MyCommand\r\n            RequestUri            = $ErrorObject.TargetObject.RequestUri\r\n            ScriptStackTrace      = $ErrorObject.ScriptStackTrace\r\n            ErrorMessage          = ''\r\n        }\r\n        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {\r\n            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message\r\n        }\r\n        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {\r\n            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()\r\n        }\r\n        Write-Output $httpErrorObj\r\n    }\r\n}\r\n\r\nfunction Resolve-MicrosoftGraphAPIErrorMessage {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Parameter(Mandatory,\r\n            ValueFromPipeline\r\n        )]\r\n        [object]$ErrorObject\r\n    )\r\n    process {\r\n        try {\r\n            $errorObjectConverted = $ErrorObject | ConvertFrom-Json -ErrorAction Stop\r\n\r\n            if ($null -ne $errorObjectConverted.error_description) {\r\n                $errorMessage = $errorObjectConverted.error_description\r\n            }\r\n            elseif ($null -ne $errorObjectConverted.error) {\r\n                if ($null -ne $errorObjectConverted.error.message) {\r\n                    $errorMessage = $errorObjectConverted.error.message\r\n                    if ($null -ne $errorObjectConverted.error.code) { \r\n                        $errorMessage = $errorMessage + \" Error code: $($errorObjectConverted.error.code)\"\r\n                    }\r\n                }\r\n                else {\r\n                    $errorMessage = $errorObjectConverted.error\r\n                }\r\n            }\r\n            else {\r\n                $errorMessage = $ErrorObject\r\n            }\r\n        }\r\n        catch {\r\n            $errorMessage = $ErrorObject\r\n        }\r\n\r\n        Write-Output $errorMessage\r\n    }\r\n}\r\n#endregion functions\r\n\r\n# Create Guest invitation\r\ntry {\r\n    # Setup Connection with Entra/Exo\r\n    Write-Verbose 'connecting to MS-Entra'\r\n    $certificate = Get-MSEntraCertificate\r\n    $entraToken = Get-MSEntraAccessToken -Certificate $certificate\r\n    \r\n        #Add the authorization header to the request\r\n    $authorization = @{\r\n            Authorization = \"Bearer $entraToken\";\r\n            'Content-Type' = \"application/json\";\r\n            Accept = \"application/json\";\r\n            'ConsistencyLevel' = 'eventual'\r\n    } \r\n\r\n    Write-Verbose \"Creating invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress)). Invitation object: $($invitation | ConvertTo-Json -Depth 10)\"\r\n\r\n    $baseUri = \"https://graph.microsoft.com/\"\r\n    $body = $invitation | ConvertTo-Json -Depth 10\r\n    $splatWebRequest = @{\r\n        Uri     = \"$baseUri/v1.0/invitations\"\r\n        Headers = $authorization\r\n        Method  = 'POST'\r\n        Body    = ([System.Text.Encoding]::UTF8.GetBytes($body))\r\n    }\r\n    $createInvitationResponse = $null\r\n    $createInvitationResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false\r\n    Write-Information \"Successfully created invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress))\"\r\n\r\n    $Log = @{\r\n        Action            = \"CreateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"EntraID\" # optional (free format text) \r\n        Message           = \"Successfully created invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress))\" # required (free format text) \r\n        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = \"$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUserEmailAddress))\" # optional (free format text) \r\n        TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) \r\n    }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n}\r\ncatch {\r\n    # Clean up error variables\r\n    $verboseErrorMessage = $null\r\n    $auditErrorMessage = $null\r\n\r\n    $ex = $PSItem\r\n    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n        $errorObject = Resolve-HTTPError -ErrorObject $ex\r\n\r\n        $verboseErrorMessage = $errorObject.ErrorMessage\r\n\r\n        $auditErrorMessage = Resolve-MicrosoftGraphAPIErrorMessage -ErrorObject $errorObject.ErrorMessage\r\n    }\r\n\r\n    # If error message empty, fall back on $ex.Exception.Message\r\n    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {\r\n        $verboseErrorMessage = $ex.Exception.Message\r\n    }\r\n    if ([String]::IsNullOrEmpty($auditErrorMessage)) {\r\n        $auditErrorMessage = $ex.Exception.Message\r\n    }\r\n\r\n    Write-Verbose \"Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)\"\r\n\r\n    $Log = @{\r\n        Action            = \"CreateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"EntraID\" # optional (free format text) \r\n        Message           = \"Error creating invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress)). Error message: $($auditErrorMessage)\" # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = \"$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUserEmailAddress))\" # optional (free format text) \r\n        TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) \r\n    }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n\r\n    throw \"Error creating invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress)). Error message: $($auditErrorMessage)\"\r\n}\r\n\r\n# Add account created from invitation to group\r\ntry {\r\n    foreach ($group in $groupsToAdd) {\r\n        try {\r\n            Write-Verbose \"Adding EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID group '$($group.name) ($($group.id))'\"\r\n\r\n            $body = @{ \"@odata.id\" = \"https://graph.microsoft.com/v1.0/users/$($createInvitationResponse.invitedUser.id)\" } | ConvertTo-Json -Depth 10\r\n            $splatWebRequest = @{\r\n                Uri     = \"$baseUri/v1.0/groups/$($group.id)/members\" + '/$ref'\r\n                Headers = $authorization\r\n                Method  = 'POST'\r\n                Body    = ([System.Text.Encoding]::UTF8.GetBytes($body))\r\n            }\r\n            $addGroupmemberResponse = $null\r\n            $addGroupmemberResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false\r\n\r\n            Write-Information \"Successfully added EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID group '$($group.name) ($($group.id))'\"\r\n\r\n            $Log = @{\r\n                Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                System            = \"EntraID\" # optional (free format text) \r\n                Message           = \"Successfully added EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID group '$($group.name) ($($group.id))'.\" # required (free format text) \r\n                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                TargetDisplayName = \"$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))\" # optional (free format text) \r\n                TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) \r\n            }\r\n            #send result back  \r\n            Write-Information -Tags \"Audit\" -MessageData $log\r\n        }\r\n        catch {\r\n            # Clean up error variables\r\n            $verboseErrorMessage = $null\r\n            $auditErrorMessage = $null\r\n\r\n            $ex = $PSItem\r\n            if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n                $errorObject = Resolve-HTTPError -ErrorObject $ex\r\n\r\n                $verboseErrorMessage = $errorObject.ErrorMessage\r\n\r\n                $auditErrorMessage = Resolve-MicrosoftGraphAPIErrorMessage -ErrorObject $errorObject.ErrorMessage\r\n            }\r\n\r\n            # If error message empty, fall back on $ex.Exception.Message\r\n            if ([String]::IsNullOrEmpty($verboseErrorMessage)) {\r\n                $verboseErrorMessage = $ex.Exception.Message\r\n            }\r\n            if ([String]::IsNullOrEmpty($auditErrorMessage)) {\r\n                $auditErrorMessage = $ex.Exception.Message\r\n            }\r\n\r\n            Write-Verbose \"Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)\"\r\n\r\n            if ($_ -like \"*One or more added object references already exist for the following modified properties*\") {\r\n                $Log = @{\r\n                    Action            = \"UpdateResource\" # optional. ENUM (undefined = default) \r\n                    System            = \"EntraID\" # optional (free format text) \r\n                    Message           = \"EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' is already a member of group '$($group.name) ($($group.id))'\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = \"$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))\" # optional (free format text) \r\n                    TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) \r\n                }\r\n                #send result back  \r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n            else {\r\n                $Log = @{\r\n                    Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"EntraID\" # optional (free format text) \r\n                    Message           = \"Could not add EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID group '$($group.name) ($($group.id))'. Error message: $($auditErrorMessage)\" # required (free format text) \r\n                    IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = \"$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))\" # optional (free format text) \r\n                    TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) \r\n                }\r\n                #send result back  \r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n\r\n                Write-Error \"Error adding EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID group '$($group.name) ($($group.id))'. Error message: $($auditErrorMessage)\"\r\n            }\r\n        }\r\n    }\r\n}\r\ncatch {\r\n    throw \"Error adding EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID groups '$($groupsToAdd|ConvertTo-Json)'. Error message: $($auditErrorMessage)\"\r\n}\r\n\r\n\r\n# # Optional: Update account created from invitation\r\n# try {\r\n#     Write-Verbose \"Updating account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'. Account object: $($updateAccount | ConvertTo-Json -Depth 10)\"\r\n\r\n#     $body = $updateAccount | ConvertTo-Json -Depth 10\r\n#     $splatWebRequest = @{\r\n#         Uri     = \"$baseUri/v1.0/users/$($createInvitationResponse.invitedUser.id)\"\r\n#         Headers = $headers\r\n#         Method  = 'PATCH'\r\n#         Body    = ([System.Text.Encoding]::UTF8.GetBytes($body))\r\n#     }\r\n#     $updateAccountResponse = $null\r\n#     $updateAccountResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false\r\n#     Write-Information \"Successfully updated account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'\"\r\n\r\n#     $Log = @{\r\n#         Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n#         System            = \"EntraID\" # optional (free format text) \r\n#         Message           = \"Successfully updated account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'\" # required (free format text) \r\n#         IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n#         TargetDisplayName = \"$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))\" # optional (free format text) \r\n#         TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) \r\n#     }\r\n#     #send result back  \r\n#     Write-Information -Tags \"Audit\" -MessageData $log\r\n# }\r\n# catch {\r\n#     # Clean up error variables\r\n#     $verboseErrorMessage = $null\r\n#     $auditErrorMessage = $null\r\n\r\n#     $ex = $PSItem\r\n#     if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n#         $errorObject = Resolve-HTTPError -Error $ex\r\n\r\n#         $verboseErrorMessage = $errorObject.ErrorMessage\r\n\r\n#         $auditErrorMessage = Resolve-MicrosoftGraphAPIErrorMessage -ErrorObject $errorObject.ErrorMessage\r\n#     }\r\n\r\n#     # If error message empty, fall back on $ex.Exception.Message\r\n#     if ([String]::IsNullOrEmpty($verboseErrorMessage)) {\r\n#         $verboseErrorMessage = $ex.Exception.Message\r\n#     }\r\n#     if ([String]::IsNullOrEmpty($auditErrorMessage)) {\r\n#         $auditErrorMessage = $ex.Exception.Message\r\n#     }\r\n\r\n#     Write-Verbose \"Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)\"\r\n\r\n#     $Log = @{\r\n#         Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n#         System            = \"EntraID\" # optional (free format text) \r\n#         Message           = \"Error updating account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'. Error message: $($auditErrorMessage)\" # required (free format text) \r\n#         IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n#         TargetDisplayName = \"$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))\" # optional (free format text) \r\n#         TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) \r\n#     }\r\n#     #send result back  \r\n#     Write-Information -Tags \"Audit\" -MessageData $log\r\n\r\n#     throw \"Error updating account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'. Error message: $($auditErrorMessage)\"\r\n# }","runInCloud":true}
'@ 

Invoke-HelloIDDelegatedForm -DelegatedFormName $delegatedFormName -DynamicFormGuid $dynamicFormGuid -AccessGroups $delegatedFormAccessGroupGuids -Categories $delegatedFormCategoryGuids -UseFaIcon "True" -FaIcon "fa fa-user" -task $tmpTask -returnObject ([Ref]$delegatedFormRef) 
<# End: Delegated Form #>

