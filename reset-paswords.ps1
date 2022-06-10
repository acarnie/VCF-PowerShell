
# Create new passord for AD Accounts
$NewPwd = ConvertTo-SecureString "VMware123!" -AsPlainText -Force

# Import ActiveDirectory module
Import-module ActiveDirectory
# Get the list of users from a text file.
$ListOfUsers = Get-Content 'C:\Users\Administrator\Documents\VCF Scripts\adusers.txt'
 foreach ($user in $ListOfUsers) {
     # Assign the new password to each user.
     Set-ADAccountPassword $user -NewPassword $NewPwd -Reset
     # Display userid and new password on the console.
     Write-Host $user, $Password
 }