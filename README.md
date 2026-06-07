# User Onboarding / Offboarding Automation
PowerShell automation project for IT user onboarding, offboarding, group assignment, CSV input, and audit logging.

## Overview

This is a PowerShell-based IT automation side project designed to demonstrate common user lifecycle workflows used in IT Support, Helpdesk, Desktop Support, and Junior System Administrator roles.

The project includes sample workflows for onboarding and offboarding users from CSV files. It is designed to show how repetitive IT administration tasks can be standardized, validated, and logged for better consistency.

This project can be structured to support both traditional Active Directory environments and Microsoft Entra ID environments through separate script versions.

## Features

- Create new user accounts from a CSV file
- Add users to predefined groups
- Disable user accounts during offboarding
- Remove users from groups
- Generate audit logs
- Validate required CSV fields
- Support sample data for safe testing



## Onboarding

- Onboarding CSV file name: new_users_sample.csv


- new_users_sample.csv:

  
FirstName,LastName,Username,Department,JobTitle,Groups
John,Smith,jsmith,IT,Helpdesk Technician,"IT Support;VPN Users"
Amy,Chen,achen,Finance,Accounting Assistant,"Finance Team;M365 Standard"
David,Lee,dlee,Operations,Operations Coordinator,"Operations Team;VPN Users"
Samantha,Wong,swong,HR,HR Assistant,"HR Team;M365 Standard"
Michael,Brown,mbrown,Sales,Sales Representative,"Sales Team;CRM Users"


- Onboarding CSV file Location: New_User/new_users_sample.csv



- The onboarding script file name: UserOnboarding.ps1



- onboarding script file Location: scripts/UserOnboarding.ps1



- Command: .\scripts\UserOnboarding.ps1 -CsvPath .\New_User\new_users_sample.csv



- Meaning: Run the onboarding PowerShell script and use new_users_sample.csv as the input file.





## Offboarding
- Offboarding CSV file name: offboarding_users_sample.csv

- offboarding_users_sample.csv:

  Username,FullName,Department,Reason,RemoveGroups
jsmith,John Smith,IT,Resigned,"IT Support;VPN Users"
achen,Amy Chen,Finance,Contract Ended,"Finance Team;M365 Standard"
dlee,David Lee,Operations,Transferred,"Operations Team;VPN Users"


- Offboarding CSV file Location: Offboard_User/offboarding_users_sample.csv

- The offboarding script file name: UserOffboarding.ps1

- offboarding script file Location: scripts/UserOffboarding.ps1

- Command: .\scripts\UserOffboarding.ps1 -CsvPath .\New_User\offboarding_users_sample.csv

- Meaning: Run the offboarding script and use the offboarding users CSV file as input.

## Security Notes

This project uses fake sample data only.

No real company information, passwords, tenant IDs, server names, or internal account details are included.
