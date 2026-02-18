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
