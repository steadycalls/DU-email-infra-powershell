# Windows Setup Guide

This guide provides step-by-step instructions for setting up and running the Email Infrastructure Automation on Windows with PowerShell 7.

## Prerequisites

Before you begin, ensure you have:

1. **PowerShell 7+** installed on your Windows machine
   - Download from: https://github.com/PowerShell/PowerShell/releases
   - Or install via winget: `winget install Microsoft.PowerShell`

2. **Forward Email API Key**
   - Log in to https://forwardemail.net/
   - Navigate to My Account → Security
   - Generate or copy your API key

3. **Cloudflare API Token**
   - Log in to https://dash.cloudflare.com/
   - Go to My Profile → API Tokens
   - Create a token with "Edit zone DNS" permissions
   - Select the zones (domains) you want to manage

## Step 1: Clone or Download the Repository

If you have Git installed:

```powershell
git clone https://github.com/steadycalls/DU-email-infra-powershell.git
cd DU-email-infra-powershell
```

Or download the ZIP file from GitHub and extract it.

## Step 2: Set Execution Policy

PowerShell's execution policy may prevent scripts from running. To allow scripts:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

When prompted, type `A` (Yes to All) and press Enter.

## Step 3: Configure API Credentials

1. **Copy the environment template:**

   ```powershell
   Copy-Item .env.example .env
   ```

2. **Edit the `.env` file** with Notepad or your preferred text editor:

   ```powershell
   notepad .env
   ```

3. **Add your API credentials:**

   ```dotenv
   # Forward Email API Key (required)
   FORWARD_EMAIL_API_KEY=your_actual_forward_email_api_key_here

   # Cloudflare API Token (required)
   CLOUDFLARE_API_TOKEN=your_actual_cloudflare_api_token_here

   # Cloudflare Account ID (optional)
   CLOUDFLARE_ACCOUNT_ID=your_cloudflare_account_id_here
   ```

4. **Save and close** the file.

## Step 4: Load Environment Variables

PowerShell on Windows does not automatically load `.env` files. Use the provided helper script:

```powershell
.\Load-Environment.ps1
```

This script will:
- Read the `.env` file
- Load all variables into the current PowerShell session
- Display which variables were loaded (with masked sensitive values)

**Important:** You need to run `Load-Environment.ps1` in **every new PowerShell session** before running the automation scripts.

## Step 5: Test Your Setup

Run the test script to validate your configuration:

```powershell
.\Test-Setup.ps1
```

The test script will check:
- PowerShell version (must be 7+)
- Module loading
- Environment variables
- API connectivity

If all tests pass, you're ready to go!

## Step 6: Prepare Your Domain List

Create a file called `data\domains.txt` with your domains (one per line):

```text
example.com
example.net
example.org
```

You can create this file with Notepad:

```powershell
notepad data\domains.txt
```

## Step 7: Run the Automation

Execute the main script:

```powershell
.\Setup-EmailInfrastructure.ps1 -DomainsFile data\domains.txt
```

The script will process each domain through the complete pipeline.

## Common Windows-Specific Issues

### Issue: "Cannot be loaded because running scripts is disabled"

**Solution:** Run this command to allow scripts:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Issue: "Environment variables not set"

**Solution:** Make sure you run `.\Load-Environment.ps1` before running the automation scripts.

### Issue: PowerShell 5.1 instead of PowerShell 7

**Solution:** Make sure you're running PowerShell 7 (pwsh.exe), not Windows PowerShell 5.1 (powershell.exe).

To check your version:

```powershell
$PSVersionTable.PSVersion
```

You should see version 7.x or higher.

### Issue: "File path not found" errors

**Solution:** Windows uses backslashes (`\`) in file paths. The scripts handle this automatically, but when specifying paths manually, use:

```powershell
# Correct for Windows
.\Setup-EmailInfrastructure.ps1 -DomainsFile data\domains.txt

# Also works (PowerShell accepts forward slashes)
.\Setup-EmailInfrastructure.ps1 -DomainsFile data/domains.txt
```

## Quick Reference: Complete Workflow

Here's the complete workflow in one place:

```powershell
# 1. Open PowerShell 7 (pwsh.exe)

# 2. Navigate to the project directory
cd C:\path\to\DU-email-infra-powershell

# 3. Set execution policy (first time only)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 4. Load environment variables (required for each new session)
.\Load-Environment.ps1

# 5. Test your setup
.\Test-Setup.ps1

# 6. Run the automation
.\Setup-EmailInfrastructure.ps1 -DomainsFile data\domains.txt
```

## Monitoring Progress

- **Console Output**: Real-time status updates with color-coded messages
- **Log File**: Detailed logs in `logs\automation.log`
- **State File**: Current status of all domains in `data\state.json`

## Interrupting and Resuming

You can safely interrupt the script at any time by pressing `Ctrl+C`. When you run it again, it will resume from where it left off.

## Getting Help

For more detailed information, see:
- [README.md](README.md) - Project overview
- [QUICKSTART.md](QUICKSTART.md) - Quick start guide
- [USAGE.md](USAGE.md) - Detailed usage examples
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [ARCHITECTURE.md](ARCHITECTURE.md) - Technical architecture
