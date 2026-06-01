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

# Global variables
# Outcommented as these are set from Global Variables
# $EntraIdTenantId = ""
# $EntraIdAppId = ""
# $EntraIdCertificateBase64String = ""
# $EntraIdCertificatePassword = ""

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
function Resolve-MicrosoftGraphAPIError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json -ErrorAction Stop)
            if ($errorDetailsObject.error_description) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error_description
            }
            elseif ($errorDetailsObject.error.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.code): $($errorDetailsObject.error.message)"
            }
            elseif ($errorDetailsObject.error.details.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.details.code): $($errorDetailsObject.error.details.message)"
            }
            else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function Get-MSEntraAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Certificate,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $AppId,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $TenantId
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
            'iss' = "$($AppId)"
            'sub' = "$($AppId)"
            'aud' = "https://login.microsoftonline.com/$($TenantId)/oauth2/token"
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
            client_id             = $AppId
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion      = $jwtToken
            resource              = 'https://graph.microsoft.com'
        }

        $createEntraAccessTokenSplatParams = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/token"
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
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificateBase64String,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificatePassword
    )
    try {
        $rawCertificate = [system.convert]::FromBase64String($CertificateBase64String)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        Write-Output $certificate
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion functions

# Create Guest invitation
try {
    # Convert base64 certificate string to certificate object
    $actionMessage = "converting base64 certificate string to certificate object"
    $certificate = Get-MSEntraCertificate -CertificateBase64String $EntraIdCertificateBase64String -CertificatePassword $EntraIdCertificatePassword
    Write-Verbose "Converted base64 certificate string to certificate object"

    # Create access token
    $actionMessage = "creating access token"
    $entraToken = Get-MSEntraAccessToken -Certificate $certificate -AppId $EntraIdAppId -TenantId $EntraIdTenantId
    Write-Verbose "Created access token"

    # Create headers
    $actionMessage = "creating headers"
    $headers = @{
        "Authorization"    = "Bearer $($entraToken)"
        "Accept"           = "application/json"
        "Content-Type"     = "application/json"
        "ConsistencyLevel" = "eventual" # Needed to filter on specific attributes (https://docs.microsoft.com/en-us/graph/aad-advanced-queries)
    }
    Write-Verbose "Created headers"

    # Invite user
    # API docs: https://learn.microsoft.com/en-us/graph/api/invitation-post?view=graph-rest-1.0
    $actionMessage = "creating invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress))"
            
    $body = $invitation | ConvertTo-Json -Depth 10
    $splatWebRequest = @{
        Uri     = "https://graph.microsoft.com/v1.0/invitations"
        Headers = $authorization
        Method  = 'POST'
        Body    = ([System.Text.Encoding]::UTF8.GetBytes($body))
    }
    $createInvitationResponse = $null
    $createInvitationResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false

    $Log = @{
        Action            = "CreateAccount" # optional. ENUM (undefined = default) 
        System            = "EntraID" # optional (free format text) 
        Message           = "Created invitation for $($invitation.invitedUserDisplayName) ($($invitation.invitedUserEmailAddress))" # required (free format text) 
        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = "$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUserEmailAddress))" # optional (free format text) 
        TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) 
    }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log

    # Add account created from invitation to group  
    foreach ($groupToAdd in $groupsToAdd) {
        try {
            # Add member to group
            # API docs: https://learn.microsoft.com/en-us/graph/api/group-post-members?view=graph-rest-1.0&tabs=http
            $actionMessage = "adding user [$($user.displayName)] with id [$($user.id)] as member to group [$($groupToAdd.displayName)] with id [$($groupToAdd.id)]"
            $addGroupMemberBody = @{ 
                "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($user.id)"
            }
            $addGroupMemberSplatParams = @{
                Uri         = "https://graph.microsoft.com/v1.0/groups/$($groupToAdd.id)/members/`$ref"
                Headers     = $headers
                Method      = "POST"
                Body        = ($addGroupMemberBody | ConvertTo-Json -Depth 10)
                Verbose     = $false
                ErrorAction = "Stop"
            }
            $addGroupMemberResponse = Invoke-RestMethod @addGroupMemberSplatParams

            $Log = @{
                Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                System            = "EntraID" # optional (free format text) 
                Message           = "Added user [$($user.displayName)] with id [$($user.id)] as member to group [$($groupToAdd.displayName)] with id [$($groupToAdd.id)]." # required (free format text) 
                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                TargetDisplayName = $user.displayName # optional (free format text)
                TargetIdentifier  = $user.id # optional (free format text)
            }
            Write-Information -Tags "Audit" -MessageData $log
        }
        catch {
            $ex = $PSItem
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObj = Resolve-MicrosoftGraphAPIError -ErrorObject $ex
                $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
                $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
            }
            else {
                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            }

            if ($auditMessage -like "*One or more added object references already exist for the following modified properties: 'members'*") {
                $Log = @{
                    Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                    System            = "EntraID" # optional (free format text) 
                    Message           = "Skipped $($actionMessage). Reason: User is already member of this group." # required (free format text) 
                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = $user.displayName # optional (free format text)
                    TargetIdentifier  = $user.id # optional (free format text)
                }
                Write-Information -Tags "Audit" -MessageData $log
            }
            else {
                $Log = @{
                    Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                    System            = "EntraID" # optional (free format text) 
                    Message           = $auditMessage # required (free format text) 
                    IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = $user.displayName # optional (free format text)
                    TargetIdentifier  = $user.id # optional (free format text)
                }
                Write-Information -Tags "Audit" -MessageData $log
                Write-Warning $warningMessage
                Write-Error $auditMessage
            }
        }
    }

    # # Optional: Update account created from invitation
    # $actionMessage "updating account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'. Account object: $($updateAccount | ConvertTo-Json -Depth 10)"

    # $body = $updateAccount | ConvertTo-Json -Depth 10
    # $splatWebRequest = @{
    #     Uri     = "https://graph.microsoft.com/v1.0/users/$($createInvitationResponse.invitedUser.id)"
    #     Headers = $headers
    #     Method  = 'PATCH'
    #     Body    = ([System.Text.Encoding]::UTF8.GetBytes($body))
    # }
    # $updateAccountResponse = $null
    # $updateAccountResponse = Invoke-RestMethod @splatWebRequest -Verbose:$false

    # $Log = @{
    #     Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
    #     System            = "EntraID" # optional (free format text) 
    #     Message           = "Updated account '$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))'" # required (free format text) 
    #     IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
    #     TargetDisplayName = "$($createInvitationResponse.invitedUserDisplayName) ($($createInvitationResponse.invitedUser.id))" # optional (free format text) 
    #     TargetIdentifier  = $createInvitationResponse.invitedUser.id # optional (free format text) 
    # }
    # #send result back  
    # Write-Information -Tags "Audit" -MessageData $log
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-MicrosoftGraphAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $Log = @{
        Action            = "undefined" # optional. ENUM (undefined = default) 
        System            = "EntraID" # optional (free format text) 
        Message           = $auditMessage # required (free format text) 
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $user.displayName # optional (free format text)
        TargetIdentifier  = $user.id # optional (free format text)
    }
    Write-Information -Tags "Audit" -MessageData $log
    Write-Warning $warningMessage
    Write-Error $auditMessage
}
