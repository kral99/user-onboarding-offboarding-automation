# User Onboarding / Offboarding Automation
PowerShell automation project for IT user onboarding, offboarding, group assignment, CSV input, and audit logging.

## Overview

This is a PowerShell-based IT automation side project designed to streamline common user lifecycle tasks, including onboarding, offboarding, group assignment, CSV-based input, and audit logging.

The project demonstrates practical scripting skills for IT Support, Helpdesk, Desktop Support, and Junior System Administrator roles.

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


- Onboarding CSV file Location: New User/new_users_sample.csv



- The onboarding script file name: New-UserOnboarding.ps1



- onboarding script file Location: scripts/New-UserOnboarding.ps1



- Command: .\scripts\New-UserOnboarding.ps1 -CsvPath .\New User\new_users_sample.csv



- Meaning: Run the onboarding PowerShell script and use new_users_sample.csv as the input file.





## Offboarding
Onboarding CSV file name

new_users_sample.csv

offboarding CSV file name

offboarding_users_sample.csv
