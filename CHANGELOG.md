# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.1] - 2026-06-01

### Fixed

- Removed example values from global variables in all-in-one setup script (`createform.ps1`)
  - Cleared example GUID values for `EntraIDAppId` and `EntraIDtenantID` variables
  - Removed example placeholder value for `companyName` variable

## [2.0.0] - 2026-06-01

This is a major release that migrates from Azure AD to Microsoft Entra ID terminology and replaces client secret authentication with certificate-based authentication. This release includes breaking changes that require reconfiguration of global variables and App Registration settings.

### Added

- Added GitHub Actions workflow for automated release creation (`Create Release` workflow)
- Added GitHub Actions workflow to verify CHANGELOG.md updates on pull requests (`Verify CHANGELOG Updated` workflow)
- Added data source to check email address uniqueness (`EntraID-Check-EmailAddress-Unique`)
  - Validates that email addresses are not already in use before sending invitations
  - Queries user mail and proxyAddresses properties to prevent duplicate invitations
- Added data source to retrieve all manageable Entra ID groups (`EntraID-Get-All-Groups`)
  - Filters groups to include Microsoft 365 groups (Unified) and cloud-only security groups
  - Excludes dynamic membership groups, on-premises synced groups, mail-enabled security groups, and distribution groups
- Added certificate-based authentication functions (`Get-MSEntraCertificate` and `Get-MSEntraAccessToken`)
  - Implements JWT token generation with X.509 certificate signing
  - Uses SHA-256 certificate thumbprint (`x5t#S256`) for enhanced security
- Added pagination support with `@odata.nextLink` for complete result sets
- Added comprehensive error handling with `Resolve-MicrosoftGraphAPIError` function
- Added support for optional personal message in guest invitations
- Added `companyName` global variable for invitation message branding

### Changed

- **BREAKING:** Migrated from Azure AD terminology to Microsoft Entra ID terminology throughout all scripts, documentation, and configuration files
- **BREAKING:** Updated global variable names to use Entra ID naming convention:
  - Old: `AADTenantId` → New: `EntraIdTenantId`
  - Old: `AADAppId` → New: `EntraIdAppId`
  - Old: `AADAppSecret` → New: `EntraIdCertificateBase64String` and `EntraIdCertificatePassword`
- **BREAKING:** Replaced client secret authentication with certificate-based authentication for Microsoft Graph API access
  - Now uses JWT (JSON Web Tokens) generated from X.509 certificates
  - Requires certificate to be uploaded to Entra ID App Registration
  - Certificate must be provided as Base64-encoded string with password
- **BREAKING:** Refactored data source names from Azure AD to Entra ID naming:
  - Old: `AzureAD-Guest-Invite - Groups` → New: `EntraID-Get-All-Groups`
  - Added: `EntraID-Check-EmailAddress-Unique` (new functionality)
- Updated task name from "AzureAD Guest - Invite" to "Entra ID Guest - Invite"
- Updated API permissions to minimal required set:
  - `User.Read.All` - To read user information and check if email addresses are already in use
  - `User.Invite.All` - To send guest invitations
  - `Group.Read.All` - To read group information
  - `GroupMember.ReadWrite.All` - To manage group memberships
- Enhanced delegated form with improved user experience and validation
  - Email address uniqueness validation before sending invitation
  - Optional personal message support
  - Improved field layout and error messaging
- Improved error handling for duplicate member additions with graceful skipping and audit logging
- Updated guest invitation operations to use Microsoft Graph API v1.0:
  - Send invitation: `POST /v1.0/invitations`
  - Check user email: `GET /v1.0/users`
  - List groups: `GET /v1.0/groups`
  - Add member: `POST /v1.0/groups/{groupId}/members/$ref`
- Updated README.md with comprehensive documentation including:
  - Best practice guidance on using HelloID Products vs. Delegated Forms
  - Certificate-based authentication setup instructions
  - API permissions requirements
  - Connection settings
  - Remarks on email validation, group filtering, and error handling
  - Complete API endpoint documentation
- Improved code formatting and consistency across all PowerShell scripts
- Enhanced audit logging for all guest invitation and group membership operations
- Updated all-in-one setup script with new global variable names and certificate support

### Deprecated

- Deprecated support for Azure AD naming convention in global variables (use Entra ID naming convention instead)
- Deprecated client secret authentication method (use certificate-based authentication instead)

### Removed

- Removed support for client secret-based authentication in favor of certificate-based authentication
- Removed Azure AD terminology from all scripts and documentation
- Removed excessive API permissions that were not required for guest invitation operations

### Fixed

- Fixed pagination handling to ensure all groups are retrieved when result sets exceed page limits
- Fixed error handling to provide more detailed error messages with line numbers and friendly messages
- Fixed group filtering to properly exclude unsupported group types (dynamic, synced, distribution groups)
- Fixed email address validation to check both mail and proxyAddresses properties

## [1.0.0] - 2021-09-02

### Added

- Initial release of HelloID-Conn-SA-Full-AzureAD-Guest-Invite
- Guest user invitation functionality for Microsoft Azure AD
- Form-based guest user invitation with email address entry
- Support for entering guest user's given name and last name
- Optional group membership assignment during invitation
  - Select multiple Microsoft 365 or Security groups
  - Groups are assigned after invitation is sent
- Client secret-based authentication for Microsoft Graph API
- Data source for retrieving Azure AD groups (`AzureAD-Guest-Invite - Groups`)
- Task for sending guest invitations and managing group memberships
- All-in-one setup script for HelloID form deployment
- Basic error handling and audit logging
- Support for custom invitation redirect URL

### Changed

### Deprecated

### Removed

### Fixed
