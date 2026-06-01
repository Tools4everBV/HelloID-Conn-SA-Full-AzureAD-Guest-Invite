# HelloID-Conn-SA-Full-Microsoft-Entra-ID-GuestInvite

| :information_source: Information |
|:--------------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

## Description

HelloID-Conn-SA-Full-Microsoft-Entra-ID-GuestInvite is a delegated form designed for use with HelloID Service Automation (SA). It can be imported into HelloID and customized according to your requirements.

By using this delegated form, you can invite external users (guests) to Microsoft Entra ID and optionally add them to selected groups. The following options are available:

1. Search and enter the guest user's email address
2. Enter given name and last name
3. Add an optional personal message in the invitation
4. Select Microsoft 365 or Security groups to add the guest to
5. Send the invitation and apply selected group memberships

## Getting started

### Requirements

#### App Registration & Certificate Setup

Before implementing this connector, make sure to configure a Microsoft Entra ID App Registration. During the setup process, you'll create a new App Registration in the Entra portal, assign the necessary API permissions (such as user and group read/write), and generate and assign a certificate.

Follow the official Microsoft documentation for creating an App Registration and setting up certificate-based authentication:

- [App-only authentication with certificate](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps#set-up-app-only-authentication)

#### HelloID-specific configuration

Once you have completed the Microsoft setup and followed their best practices, configure the following HelloID-specific requirements.

- **API Permissions** (Application permissions):
  - `User.Read.All` - To read user information and check if email addresses are already in use
  - `User.Invite.All` - To send guest invitations
  - `Group.Read.All` - To read group information
  - `GroupMember.ReadWrite.All` - To manage group memberships
- **Certificate:**
  - Upload the public key file (.cer) in Entra ID
  - Provide the certificate as a Base64 string in HelloID.

> [!NOTE]
> **App registration permissions** depend on the functionality you use. For example, if you do not create teams using a resource script, read/write permissions are not required.

#### Convert .pfx to base64 string
HelloID requires a base64 string to import the certificate. With the example below, it is possible to create a base64 string

```Powershell
$filePath = 'C:\Cert'
$pfxCertName = 'Cert.pfx'
$pfxPath = "$filePath\$pfxCertName"

$fileContentBytes = [System.IO.File]::ReadAllBytes("$pfxPath")
[System.Convert]::ToBase64String($fileContentBytes) | Set-Content "$filePath\HelloID_Cert_Base64.txt"
```

### Connection settings

The following global variables must be configured in HelloID when importing and configuring the delegated form.

| Setting | Description | Mandatory |
|---------|-------------|----------:|
| EntraIdTenantId | The unique identifier (ID) of the tenant in Microsoft Entra ID | Yes |
| EntraIdAppId | The unique identifier (ID) of the App Registration in Microsoft Entra ID | Yes |
| EntraIdCertificateBase64String | The Base64-encoded string representation of the app certificate | Yes |
| EntraIdCertificatePassword | The password associated with the app certificate | Yes |
| companyName | Branding value used in invitation messaging | No |

> Note: When running inside HelloID, `portalUrl`, `apiKey`, and `apiSecret` are provided automatically after generating and storing API credentials in the Admin panel.

### All-in-one setup script

Use the all-in-one script to create the delegated form, dynamic form, data sources, tasks, and required HelloID global variables.

## Remarks

### Certificate-Based Authentication

- **JWT Token Generation:** The connector uses certificate-based authentication to generate JSON Web Tokens (JWT) for secure communication with Microsoft Graph API. The certificate is converted from a base64 string and used to sign the JWT assertion for OAuth2 authentication.

### Group Selection

- **Supported Group Types:** The form loads Microsoft 365 and Security groups via a data source and allows multi-select assignment during invite. Distribution lists and mail-enabled security groups are not supported by the endpoints used here.

### Email Validation

- **Uniqueness Check:** Before sending an invitation, the form checks if the email address is already in use by querying existing users (checking mail and proxyAddresses properties).
- **Duplicate Prevention:** If the email address is already associated with an existing user, the form prevents sending a duplicate invitation.

### Invitation Message

- **Personal Message:** The invitation supports a personal message that will be included in the invitation email sent to the guest user.
- **Audit Logging:** Actions are logged for auditing within HelloID to track guest invitations and group assignments.

### Error Handling

- **Duplicate Member Addition:** If attempting to add a user who is already a member of a group, the operation is skipped with an appropriate audit log entry rather than failing.
- **Invalid Email Addresses:** If an invalid email address is provided, the invitation will fail with an appropriate error message.

## Development resources

### API endpoints

The following Microsoft Graph API endpoints are used by the connector:

| Endpoint | Description |
|----------|-------------|
| /v1.0/users | Check if email address is already in use |
| /v1.0/invitations | Send guest invitations |
| /v1.0/groups | List groups |
| /v1.0/groups/{id}/members/$ref | Add member |

### API documentation

- [List users](https://learn.microsoft.com/en-us/graph/api/user-list)
- [Create invitation](https://learn.microsoft.com/en-us/graph/api/invitation-post)
- [List groups](https://learn.microsoft.com/en-us/graph/api/group-list)
- [Add group member](https://learn.microsoft.com/en-us/graph/api/group-post-members)

## Getting help

> [!TIP]
> For more information on Delegated Forms, please refer to our [documentation](https://docs.helloid.com/en/service-automation/delegated-forms.html) pages.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
