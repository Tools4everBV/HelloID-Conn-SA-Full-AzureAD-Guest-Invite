# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = 'SilentlyContinue'
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# variables configured in form
#Change mapping here
$invitation = [PSCustomObject]@{
    invitedUserDisplayName  = $form.givenName + " " + $form.lastName;
    invitedUserEmailAddress = $form.email;
    sendInvitationMessage   = $true;
    inviteRedirectUrl       = "https://portal.azure.com/";
    invitedUserMessageInfo  = @{
        customizedMessageBody = $form.messageArea # "Personalized message body."
        messageLanguage = "nl-NL" # If the customizedMessageBody is specified, this property is ignored, and the message is sent using the customizedMessageBody. The language format should be in ISO 639. The default is en-US.
    }
}

$groupsToAdd = $form.groups

# # Optional, fields to updated on account created from invitation
# $updateAccount = @{
#     CompanyName = $form.company
#     Department  = $form.department
#     jobTitle    = $form.title
# }


#region functions
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

# Create Guest invitation
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

    Write-Verbose "Creating invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress)). Invitation object: $($invitation | ConvertTo-Json -Depth 10)"

    $baseUri = "https://graph.microsoft.com/"
    $body = $invitation | ConvertTo-Json -Depth 10
    $splatWebRequest = @{
        Uri     = "$baseUri/v1.0/invitations"
        Headers = $authorization
        Method  = 'POST'
        Body    = ([System.Text.Encoding]::UTF8.GetBytes($body))
    }
    $createInvitationResponse = $null
    $createInvitationResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false
    Write-Information "Successfully created invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress))"

    $Log = @{
        Action            = "CreateAccount" # optional. ENUM (undefined = default) 
        System            = "EntraID" # optional (free format text) 
        Message           = "Successfully created invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress))" # required (free format text) 
        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = "$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUserEmailAddress))" # optional (free format text) 
        TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) 
    }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log
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

    $Log = @{
        Action            = "CreateAccount" # optional. ENUM (undefined = default) 
        System            = "EntraID" # optional (free format text) 
        Message           = "Error creating invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress)). Error message: $($auditErrorMessage)" # required (free format text) 
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = "$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUserEmailAddress))" # optional (free format text) 
        TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) 
    }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log

    throw "Error creating invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress)). Error message: $($auditErrorMessage)"
}

# Add account created from invitation to group
try {
    foreach ($group in $groupsToAdd) {
        try {
            Write-Verbose "Adding EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID group '$($group.name) ($($group.id))'"

            $body = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($createInvitationResponse.invitedUser.id)" } | ConvertTo-Json -Depth 10
            $splatWebRequest = @{
                Uri     = "$baseUri/v1.0/groups/$($group.id)/members" + '/$ref'
                Headers = $authorization
                Method  = 'POST'
                Body    = ([System.Text.Encoding]::UTF8.GetBytes($body))
            }
            $addGroupmemberResponse = $null
            $addGroupmemberResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false

            Write-Information "Successfully added EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID group '$($group.name) ($($group.id))'"

            $Log = @{
                Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                System            = "EntraID" # optional (free format text) 
                Message           = "Successfully added EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID group '$($group.name) ($($group.id))'." # required (free format text) 
                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                TargetDisplayName = "$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))" # optional (free format text) 
                TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) 
            }
            #send result back  
            Write-Information -Tags "Audit" -MessageData $log
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

            if ($_ -like "*One or more added object references already exist for the following modified properties*") {
                $Log = @{
                    Action            = "UpdateResource" # optional. ENUM (undefined = default) 
                    System            = "EntraID" # optional (free format text) 
                    Message           = "EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' is already a member of group '$($group.name) ($($group.id))'" # required (free format text) 
                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = "$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))" # optional (free format text) 
                    TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) 
                }
                #send result back  
                Write-Information -Tags "Audit" -MessageData $log
            }
            else {
                $Log = @{
                    Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                    System            = "EntraID" # optional (free format text) 
                    Message           = "Could not add EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID group '$($group.name) ($($group.id))'. Error message: $($auditErrorMessage)" # required (free format text) 
                    IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = "$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))" # optional (free format text) 
                    TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) 
                }
                #send result back  
                Write-Information -Tags "Audit" -MessageData $log

                Write-Error "Error adding EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID group '$($group.name) ($($group.id))'. Error message: $($auditErrorMessage)"
            }
        }
    }
}
catch {
    throw "Error adding EntraID account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))' to EntraID groups '$($groupsToAdd|ConvertTo-Json)'. Error message: $($auditErrorMessage)"
}


# # Optional: Update account created from invitation
# try {
#     Write-Verbose "Updating account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'. Account object: $($updateAccount | ConvertTo-Json -Depth 10)"

#     $body = $updateAccount | ConvertTo-Json -Depth 10
#     $splatWebRequest = @{
#         Uri     = "$baseUri/v1.0/users/$($createInvitationResponse.invitedUser.id)"
#         Headers = $headers
#         Method  = 'PATCH'
#         Body    = ([System.Text.Encoding]::UTF8.GetBytes($body))
#     }
#     $updateAccountResponse = $null
#     $updateAccountResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false
#     Write-Information "Successfully updated account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'"

#     $Log = @{
#         Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
#         System            = "EntraID" # optional (free format text) 
#         Message           = "Successfully updated account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'" # required (free format text) 
#         IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
#         TargetDisplayName = "$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))" # optional (free format text) 
#         TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) 
#     }
#     #send result back  
#     Write-Information -Tags "Audit" -MessageData $log
# }
# catch {
#     # Clean up error variables
#     $verboseErrorMessage = $null
#     $auditErrorMessage = $null

#     $ex = $PSItem
#     if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
#         $errorObject = Resolve-HTTPError -Error $ex

#         $verboseErrorMessage = $errorObject.ErrorMessage

#         $auditErrorMessage = Resolve-MicrosoftGraphAPIErrorMessage -ErrorObject $errorObject.ErrorMessage
#     }

#     # If error message empty, fall back on $ex.Exception.Message
#     if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
#         $verboseErrorMessage = $ex.Exception.Message
#     }
#     if ([String]::IsNullOrEmpty($auditErrorMessage)) {
#         $auditErrorMessage = $ex.Exception.Message
#     }

#     Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

#     $Log = @{
#         Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
#         System            = "EntraID" # optional (free format text) 
#         Message           = "Error updating account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'. Error message: $($auditErrorMessage)" # required (free format text) 
#         IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
#         TargetDisplayName = "$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))" # optional (free format text) 
#         TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) 
#     }
#     #send result back  
#     Write-Information -Tags "Audit" -MessageData $log

#     throw "Error updating account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'. Error message: $($auditErrorMessage)"
# }
