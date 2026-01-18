# Troubleshooting Guide

This guide covers common issues you might encounter while using the Email Infrastructure Automation script and how to resolve them.

## Initial Setup

### PowerShell Version Error

- **Error**: `PowerShell 7+ required. Current version: X.X`
- **Cause**: The script is being run with an older version of PowerShell (e.g., Windows PowerShell 5.1).
- **Solution**: Ensure you are running the script in a **PowerShell 7** (pwsh.exe) terminal. You can download PowerShell 7 from the [official repository](https://github.com/PowerShell/PowerShell).

### Module Load Failure

- **Error**: `Failed to load [ModuleName] module: ...`
- **Cause**: The module files in the `modules/` directory may be corrupted, missing, or have incorrect permissions.
- **Solution**:
  1.  Ensure all module files (`.psm1`) exist in the `modules/` directory.
  2.  Re-clone the repository to get fresh copies of the files.
  3.  Check that you have read permissions for the files in the `modules/` directory.

## Configuration Errors

### Missing Environment Variables

- **Error**: `FORWARD_EMAIL_API_KEY is not set` or `CLOUDFLARE_API_TOKEN is not set`
- **Cause**: The required API credentials have not been provided.
- **Solution**:
  1.  Make sure you have created a `.env` file in the root directory of the project.
  2.  Verify that the `.env` file contains the correct keys and that you have pasted your API credentials as their values.
  3.  Ensure you are running the script from the root of the project directory where the `.env` file is located.

## API and Processing Errors

### 401 Unauthorized / 403 Forbidden

- **Error**: `Request failed with status code: 401` or `Request failed with status code: 403`
- **Cause**: The API key or token is invalid or lacks the necessary permissions.
- **Solution**:
  - **Forward Email**: Regenerate your API key from your Forward Email account settings and update it in your `.env` file.
  - **Cloudflare**: 
    1.  Verify your API token is correct.
    2.  Ensure the token has the `DNS:Edit` permission. You can check this in the Cloudflare dashboard under "My Profile" > "API Tokens".
    3.  Make sure the token is active and not expired.

### Zone Not Found for Domain

- **Error**: `Failed to configure DNS records: Zone not found for domain: example.com`
- **Cause**: The domain you are trying to process does not exist in the Cloudflare account associated with your API token.
- **Solution**:
  1.  Log in to your Cloudflare dashboard and confirm that the domain is listed as an active zone.
  2.  If the domain is in a different Cloudflare account, you will need to use an API token from that account.

### Domain Verification Timed Out

- **Error**: `Domain verification timed out after X attempts`
- **Cause**: DNS propagation is taking longer than the script's configured timeout. This can happen for various reasons, including high TTLs on existing records or slow updates from the domain registrar's nameservers.
- **Solution**:
  1.  **Wait and Retry**: The easiest solution is often to wait longer and re-run the script. The script will resume from the `Verifying` state.
  2.  **Increase Timeout**: You can increase the verification timeout by adjusting the `VerificationMaxAttempts` or `VerificationPollInterval` in your configuration (either in `.env` or a custom config file).
  3.  **Manual Check**: Manually check the DNS records for the domain using a tool like `nslookup` or an online DNS checker to see if the TXT and MX records are propagating.
     ```powershell
     nslookup -q=TXT example.com
     nslookup -q=MX example.com
     ```

### Rate Limiting

- **Warning**: `Rate limited. Waiting X seconds...`
- **Cause**: The script is making too many API requests in a short period.
- **Solution**: The script handles this automatically by pausing and retrying. If you see this frequently, consider reducing the `ConcurrentDomains` value in your configuration to slow down the processing rate.

## General Troubleshooting

### Reviewing Logs

The most important tool for troubleshooting is the log file (default: `logs/automation.log`). For detailed information, run the script with `-LogLevel DEBUG` to capture the full request and response data for each API call.

### Examining the State File

The state file (`data/state.json`) provides a snapshot of the entire process. You can inspect this file to see the exact state of any domain, including any errors it has encountered. This is useful for understanding why a specific domain failed.

### Resetting a Failed Domain

If a domain fails due to a temporary issue that you have since resolved, you can manually reset its state to retry it.

1.  Open the `data/state.json` file.
2.  Find the entry for the failed domain.
3.  Change its `State` from `Failed` back to `Pending` (to restart from the beginning) or to the last successful state (e.g., `DnsConfigured` to retry verification).
4.  Remove the entries from the `Errors` array for that domain.
5.  Save the file and re-run the script.
