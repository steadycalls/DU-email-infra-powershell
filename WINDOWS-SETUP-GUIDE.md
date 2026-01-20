# Windows Setup Guide

This guide will help you set up and run the email infrastructure automation scripts on Windows.

---

## Prerequisites

Before you begin, ensure you have:

1. **Windows PowerShell 5.1 or higher** (or PowerShell Core 7+)
2. **Git for Windows** (to clone the repository)
3. **Forward Email API Key** (from your Forward Email account)

---

## Step 1: Check PowerShell Version

Open PowerShell and run:

```powershell
$PSVersionTable.PSVersion
```

You should see version 5.1 or higher. If you have an older version, download the latest PowerShell from [Microsoft's website](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows).

---

## Step 2: Set Execution Policy

PowerShell's execution policy must allow running scripts. Run PowerShell **as Administrator** and execute:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

When prompted, type `Y` and press Enter.

**What this does**: Allows you to run locally created scripts while still requiring downloaded scripts to be signed.

---

## Step 3: Clone the Repository

Open PowerShell and navigate to your desired directory (e.g., `Documents`):

```powershell
cd "$env:USERPROFILE\Documents"
```

Clone the repository:

```powershell
git clone https://github.com/steadycalls/DU-email-infra-powershell.git
```

Navigate into the repository:

```powershell
cd DU-email-infra-powershell
```

---

## Step 4: Set Your API Key

You need to set your Forward Email API key as an environment variable.

### Option A: Set for Current Session Only (Temporary)

```powershell
$env:FORWARD_EMAIL_API_KEY = "your-api-key-here"
```

**Note**: This will only last for the current PowerShell session. You'll need to set it again if you close PowerShell.

### Option B: Set Permanently (Recommended)

1. Open PowerShell **as Administrator**
2. Run:

```powershell
[System.Environment]::SetEnvironmentVariable('FORWARD_EMAIL_API_KEY', 'your-api-key-here', 'User')
```

3. **Close and reopen PowerShell** for the change to take effect.

### Verify the API Key is Set

```powershell
$env:FORWARD_EMAIL_API_KEY
```

You should see your API key printed. If it shows nothing, the variable is not set.

---

## Step 5: Create Your Domains File

Create a file named `domains.txt` in the `data` directory with your list of domains (one per line).

```powershell
# Create the data directory if it doesn't exist
New-Item -ItemType Directory -Path "data" -Force

# Create domains.txt (edit this file with your domains)
notepad data\domains.txt
```

In Notepad, add your domains, one per line:

```
example.com
mydomain.com
anotherdomain.com
```

Save and close Notepad.

---

## Step 6: Validate Your Environment

Run the validation script to ensure everything is set up correctly:

```powershell
.\Validate-Environment.ps1
```

**Expected Output**:

- ✓ PowerShell version check passes
- ✓ Execution policy check passes
- ✓ Modules directory exists
- ✓ ForwardEmailClient.psm1 found
- ✓ Logger.psm1 found
- ✓ Data directory exists
- ✓ Logs directory exists
- ⚠ domains.txt found (or warning if you haven't created it yet)
- ✓ API key is set
- ✓ Internet connectivity
- ✓ Forward Email API reachable
- ✓ API key authentication
- ✓ Domain access

**If you see failures**:

1. **Modules not found**: Make sure you're in the correct directory (`DU-email-infra-powershell`)
2. **API key not set**: Go back to Step 4 and set your API key
3. **Execution policy restricted**: Go back to Step 2 and set the execution policy
4. **domains.txt not found**: Go back to Step 5 and create the file

---

## Step 7: Run the Diagnostic Tool

Before setting passwords in bulk, test the password API:

```powershell
.\Test-PasswordAPI.ps1
```

This will:
- Test API authentication
- Retrieve a test domain and alias
- Attempt to set a password
- Provide detailed diagnostics if it fails

**If the test passes**: You're ready to proceed!

**If the test fails**: Review the error messages and follow the recommendations. Common issues:

- **403 Forbidden**: Your Forward Email plan may not support IMAP/passwords. You may need to upgrade to the Enhanced Protection plan.
- **401 Unauthorized**: Your API key is invalid or expired. Check your API key.
- **400 Bad Request**: The alias configuration may not support passwords. Check if you're testing with a catch-all alias (*).

---

## Step 8: Set Passwords for All Aliases

Once the diagnostic test passes, run the main password-setting script:

```powershell
.\Pass3-2-SetPasswords.ps1
```

**For faster execution with parallel processing**:

```powershell
.\Pass3-2-SetPasswords.ps1 -Parallel -ThrottleLimit 10
```

**To resume an interrupted run**:

```powershell
.\Pass3-2-SetPasswords.ps1 -Resume
```

**To test without making changes (dry run)**:

```powershell
.\Pass3-2-SetPasswords.ps1 -DryRun
```

---

## Step 9: Review the Results

After the script completes, check the results:

1. **Console Output**: Shows real-time progress and summary
2. **CSV Report**: `data\pass3-2-password-results.csv` - Lists any failed aliases
3. **JSON Summary**: `data\pass3-2-summary.json` - Execution statistics
4. **Log Files**: `logs\pass3-2-set-passwords.log` - Detailed logs

**Success Rate ≥ 95%**: Excellent! Most passwords were set successfully.

**Success Rate 80-95%**: Good, but review the failures and consider re-running.

**Success Rate < 80%**: Investigate the root cause using the CSV report and diagnostic tool.

---

## Troubleshooting

### "Running scripts is disabled on this system"

**Solution**: Set the execution policy (see Step 2).

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "FORWARD_EMAIL_API_KEY environment variable is not set"

**Solution**: Set your API key (see Step 4).

```powershell
$env:FORWARD_EMAIL_API_KEY = "your-api-key-here"
```

### "Modules directory not found"

**Solution**: Make sure you're in the correct directory.

```powershell
cd "$env:USERPROFILE\Documents\DU-email-infra-powershell"
```

Then verify:

```powershell
Test-Path .\modules
```

Should return `True`.

### "Cannot access domains"

**Solution**: Your API key may not have the correct permissions. Check:

1. Your API key is correct
2. Your API key has not expired
3. Your Forward Email account has domains added

### Password setting fails with 403 Forbidden

**Solution**: Your Forward Email plan may not support IMAP/passwords. Check your plan and consider upgrading to Enhanced Protection.

---

## Next Steps

After successfully setting passwords:

1. **Verify the results**: Run `.\Export-Aliases.ps1` to generate a fresh report
2. **Check the HasPassword column**: It should now show `True` for most aliases
3. **Test IMAP access**: Try connecting to an alias via IMAP to verify the password works
4. **Integrate into your workflow**: Add the password phase to your regular automation workflow

---

## Additional Resources

- **QUICKSTART.md**: Quick reference guide
- **DEPLOYMENT.md**: Full deployment guide
- **ARCHITECTURE.md**: Technical architecture details
- **TROUBLESHOOTING.md**: Common issues and solutions
- **Forward Email API Documentation**: https://forwardemail.net/en/email-api

---

## Getting Help

If you encounter issues not covered in this guide:

1. Check the log files in the `logs` directory for detailed error messages
2. Review the CSV reports in the `data` directory for specific failures
3. Run `.\Test-PasswordAPI.ps1` to diagnose API-specific problems
4. Check the Forward Email API documentation
5. Contact Forward Email support if the issue is API-related

---

## Summary Checklist

Before running the automation:

- [ ] PowerShell 5.1 or higher installed
- [ ] Execution policy set to RemoteSigned or less restrictive
- [ ] Repository cloned to local machine
- [ ] FORWARD_EMAIL_API_KEY environment variable set
- [ ] data/domains.txt file created with your domains
- [ ] Validate-Environment.ps1 passes all checks
- [ ] Test-PasswordAPI.ps1 diagnostic test passes

Once all items are checked, you're ready to run the automation!
