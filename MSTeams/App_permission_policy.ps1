
function Set-TeamsAppPolicy
{
    param (  
    $GroupName,$AppPermissionPolicyName
    )
    process{
        #Get security group information.
        $group= Get-MsolGroup -SearchString $GroupName | Select-Object ObjectId,DisplayName
        $members=Get-MsolGroupMember -GroupObjectId $group.ObjectId -MemberObjectTypes user -all

        #Add user to App permission policy
        foreach($member in $members)
        {
            Grant-CsTeamsAppPermissionPolicy -PolicyName $AppPermissionPolicyName -Identity $member.EmailAddress
            Write-Host "Policy successfully added to $($member.EmailAddress) user " 
        } 
    }
}


function Remove-TeamsAppPolicy
{
    param (  
    $GroupName
    )
    process{

        #Get security group information.
        $group= Get-MsolGroup -SearchString $GroupName | Select-Object ObjectId,DisplayName
        $members=Get-MsolGroupMember -GroupObjectId $group.ObjectId -MemberObjectTypes user -all

        #Removing user policy, it is not possible to unassign permission policy so null value must be used.
        foreach($member in $members)
        {
            Grant-CsTeamsAppPermissionPolicy -Identity $member.EmailAddress -PolicyName $null 
            Write-Host "Policy successfully removed from $($member.EmailAddress) user " 
        } 
    }
}

function Get-policies
{
    $policy_names = Get-CsTeamsAppPermissionPolicy
    foreach($policy in $policy_names)
    {
        Write-Host "policy name is : $($policy.Identity)"
    }
}

function Set-SingleUserPolicy
{
    param (  
    $UserEmail,$AppPermissionPolicyName
    )
    process{
        Grant-CsTeamsAppPermissionPolicy -PolicyName $AppPermissionPolicyName -Identity $UserEmail
        Write-Host "Policy successfully added to $($UserEmail)"  
    }
}

function Remove-SingleUserPolicy
{
    param (  
    $UserEmail,$AppPermissionPolicyName
    )
    process{
        Grant-CsTeamsAppPermissionPolicy -Identity $UserEmail -PolicyName $null
        Write-Host "Policy successfully removed from $($UserEmail)"  
    }
}
function Show-Menu
{
    param (
        [string]$Title = 'App-Permission-Policy-Management'
    )
    Clear-Host
    Write-Host "=== $Title ==="
    Write-Host "Press '1' for AzureAD session."
    Write-Host "Press '2' for Adding policy to group."
    Write-Host "Press '3' for Removing policy to group."
    Write-Host "Press '4' for Adding single user to existing policy."
    Write-Host "Press '5' for Removing single user from existing policy."
    Write-Host "Press '6' for displaying list of existing policies."
    Write-Host "Press 'Q' to quit."
}

do

{
    Show-Menu
    $selection = Read-Host "Please make a selection"
    switch ($selection)
    {
        '1' {
            $cred = Get-Credential
            Connect-MsolService -Credential $cred    
            $session = New-CsOnlineSession -Credential $cred
            Import-PSSession $session
        }'2' {
            $group_name = Read-Host -Prompt "Enter group name "
            $app_policy_name = Read-Host -Prompt "Enter app policy name "
            Set-TeamsAppPolicy -GroupName $group_name -AppPermissionPolicyName $app_policy_name
        } '3' {
            $group_name = Read-Host -Prompt "Enter group name "
            Remove-TeamsAppPolicy -GroupName $group_name
        } '4' {
            $email = Read-Host -Prompt "Enter user email address "
            $app_policy_name = Read-Host -Prompt "Enter app policy name "
            Set-SingleUserPolicy -UserEmail $email -AppPermissionPolicyName $app_policy_name
        } '5' {
            $email = Read-Host -Prompt "Enter user email address "
            $app_policy_name = Read-Host -Prompt "Enter app policy name "
            Remove-SingleUserPolicy -UserEmail $email -AppPermissionPolicyName $app_policy_name
        } '6' {
            Get-policies
        }
    }
    pause
}
until ($selection -eq 'q')
Remove-PSSession $session
