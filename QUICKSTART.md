# Quick Start Guide

This guide will help you get started with the Email Infrastructure Automation in under 5 minutes.

## Prerequisites

- **PowerShell 7+** installed on your system
- **Forward Email account** with an API key
- **Cloudflare account** managing your domains with an API token

## Step 1: Get Your API Credentials

### Forward Email API Key

1. Log in to [Forward Email](https://forwardemail.net/)
2. Navigate to **My Account** → **Security**
3. Generate or copy your API key

### Cloudflare API Token

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Go to **My Profile** → **API Tokens**
3. Click **Create Token**
4. Use the **Edit zone DNS** template
5. Select the zones (domains) you want to manage
6. Create the token and copy it immediately (you won't see it again)

## Step 2: Configure the Script

1. **Copy the environment template:**

   ```powershell
   Copy-Item .env.example .env
   ```

2. **Edit the `.env` file** and add your credentials:

   ```dotenv
   FORWARD_EMAIL_API_KEY="your_actual_api_key_here"
   CLOUDFLARE_API_TOKEN="your_actual_api_token_here"
   ```

3. **Load environment variables** (if not automatically loaded):

   ```powershell
   Get-Content .env | ForEach-Object {
       if ($_ -match '^([^#][^=]+)=(.*)$') {
           [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
       }
   }
   ```

## Step 3: Prepare Your Domain List

Create a file called `data/domains.txt` and list your domains (one per line):

```text
example.com
example.net
example.org
```

## Step 4: Test Your Setup

Run the test script to validate your configuration:

```powershell
.\Test-Setup.ps1
```

If all tests pass, you're ready to go!

## Step 5: Run the Automation

Execute the main script:

```powershell
.\Setup-EmailInfrastructure.ps1 -DomainsFile data\domains.txt
```

The script will:
- Add each domain to Forward Email
- Configure DNS records in Cloudflare
- Verify domain ownership
- Create email aliases
- Report results

## What Happens Next?

The script will process each domain through the following stages:

1. **Adding to Forward Email** (~5 seconds per domain)
2. **Configuring DNS** (~10 seconds per domain)
3. **Verifying DNS** (~5-20 minutes, depends on DNS propagation)
4. **Creating Aliases** (~5 seconds per domain)

You can safely interrupt the script at any time (Ctrl+C). When you run it again, it will resume from where it left off.

## Monitoring Progress

- **Console Output**: Real-time status updates with color-coded messages
- **Log File**: Detailed logs in `logs/automation.log`
- **State File**: Current status of all domains in `data/state.json`

## Handling Failures

If any domains fail, they will be reported in:
- The console summary at the end
- The `data/failures.json` file with detailed error information

You can review the errors, fix any issues, and re-run the script to retry failed domains.

## Next Steps

- Read the [USAGE.md](USAGE.md) for advanced usage options
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if you encounter issues
- Review [ARCHITECTURE.md](ARCHITECTURE.md) to understand how it works

## Common First-Run Issues

### "Zone not found for domain"

**Solution**: Ensure the domain is added to your Cloudflare account and that your API token has access to it.

### "Domain verification timed out"

**Solution**: DNS propagation can take time. Wait 10-15 minutes and re-run the script. It will resume verification automatically.

### "Rate limited"

**Solution**: The script handles this automatically. If you see this frequently, reduce the `-ConcurrentDomains` parameter.
