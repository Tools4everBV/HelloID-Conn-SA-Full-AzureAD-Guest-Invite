# HelloID-Conn-SA-Full-AzureAD-Guest-Invite

| :information_source: Information |
| :------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details and prerequisites (Azure AD app registration, certificate, permissions, etc.). |

## Description
HelloID-Conn-SA-Full-AzureAD-Guest-Invite is a template designed for use with HelloID Service Automation (SA) Delegated Forms. It can be imported into HelloID and customized according to your requirements.

By using this delegated form, you can invite external users (guests) to Microsoft Entra ID (Azure AD) and optionally add them to selected groups. The form provides:
1. Entering the guest user's email address
2. Entering given name and last name
3. Optional personal message in the invitation
4. Selecting Microsoft 365 or Security groups to add the guest to
5. Sending the invitation and applying selected group memberships

## Getting started

#### App Registration & Certificate Setup

Before implementing this connector, make sure to configure a Microsoft Entra ID, an App Registration. During the setup process, you’ll create a new App Registration in the Entra portal, assign the necessary API permissions (such as user and group read/write), and generate and assign a certificate.

Follow the official Microsoft documentation for creating an App Registration and setting up certificate-based authentication:
- [App-only authentication with certificate (Exchange Online)](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps#set-up-app-only-authentication)

#### HelloID-specific configuration

Once you have completed the Microsoft setup and followed their best practices, configure the following HelloID-specific requirements.

- **API Permissions** (Application permissions):
  - `User.ReadWrite.All`
  - `Group.ReadWrite.All`
  - `GroupMember.ReadWrite.All`
  - `UserAuthenticationMethod.ReadWrite.All`
  - `User.EnableDisableAccount.All`
  - `User-PasswordProfile.ReadWrite.All`
  - `User-Phone.ReadWrite.All`
- **Certificate:**
  - Upload the public key file (.cer) in Entra ID
  - Provide the certificate as a Base64 string in HelloID. For instructions on creating the certificate and obtaining the base64 string, refer to our forum post: [Setting up a certificate for Microsoft Graph API in HelloID connectors](https://forum.helloid.com/forum/helloid-provisioning/5338-instruction-setting-up-a-certificate-for-microsoft-graph-api-in-helloid-connectors#post5338)

### Connection settings

The following user-defined (global) variables are used by the connector.

| Setting                         | Description                                        | Mandatory |
| --------------------------------| -------------------------------------------------- | --------- |
| EntraIdAppId                    | Application (client) ID of the Entra ID app       | Yes       |
| EntraIdTenantId                 | Directory (tenant) ID                             | Yes       |
| EntraIdCertificateBase64String  | Base64-encoded contents of the PFX certificate    | Yes       |
| EntraIdCertificatePassword      | Password for the PFX certificate                   | Yes       |
| companyName                     | Branding value used in invitation messaging        | No        |

> Note: When running inside HelloID, `portalUrl`, `apiKey`, and `apiSecret` are provided automatically after generating and storing API credentials in the Admin panel.

### All-in-one setup script

Use the all-in-one script to create the delegated form, dynamic form, data sources, tasks, and required HelloID global variables.

## Remarks

### Authentication (App-only via certificate)
- Uses Microsoft Graph application permissions with certificate-based client credentials. Supply `EntraIdCertificateBase64String` and `EntraIdCertificatePassword` along with `EntraIdAppId` and `EntraIdTenantId`.

### Group selection
- The form loads Microsoft 365 and Security groups via a data source and allows multi-select assignment during invite.

### Microsoft Graph API scope
- Group listing leverages supported group types from Microsoft Graph. Distribution lists and mail-enabled security groups are not supported by the endpoints used here.

### Invitation message and audit
- The invitation supports a personal message. Actions are logged for auditing within HelloID.

## Development resources

### API endpoints

The following Microsoft Graph endpoints are used by the connector:

| Endpoint                          | Description                              |
| --------------------------------- | ---------------------------------------- |
| `/invitations`                    | Send guest invitations                   |
| `/groups`                         | Retrieve Microsoft 365/Security groups   |
| `/groups/{id}/members/$ref`       | Add members to a group                   |

### API documentation
- Invitations: https://learn.microsoft.com/graph/api/invitation-post
- Groups overview: https://learn.microsoft.com/graph/api/resources/groups
- Add member to group: https://learn.microsoft.com/graph/api/group-post-members
- Microsoft Graph overview: https://learn.microsoft.com/graph

## Getting help
> :bulb: **Tip:**
> For more information on Delegated Forms, please refer to our documentation pages: https://docs.helloid.com/en/service-automation/delegated-forms.html

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/


The official HelloID documentation can be found at: https://docs.helloid.com/
