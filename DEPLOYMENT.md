# Deployment Guide: Email Infrastructure Automation v2.0

This guide provides step-by-step instructions for deploying and running the redesigned email infrastructure automation suite.

---

## Prerequisites

Before you begin, ensure your environment meets the following requirements:

1.  **PowerShell**: Version 5.1 or higher.
2.  **Execution Policy**: Must not be `Restricted`. Run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` if needed.
3.  **API Key**: Your Forward Email API key must be set as an environment variable named `FORWARD_EMAIL_API_KEY`.
4.  **File Structure**: The directory structure must be intact, with the `modules` folder at the same level as the `scripts` folder.

---

## Step 1: Validate Your Environment

Before running any automation, it is crucial to validate your environment. This step helps prevent common issues and ensures all prerequisites are met.

1.  **Open a PowerShell terminal** and navigate to the `scripts` directory.
2.  **Run the environment validation script**:

    ```powershell
    .\Validate-Environment.ps1
    ```

3.  **Review the output**:
    -   **`STATUS: READY`**: You are ready to proceed.
    -   **`STATUS: READY WITH WARNINGS`**: You can proceed, but review the warnings.
    -   **`STATUS: FAILED`**: You must fix the failed checks before continuing.

---

## Step 2: Prepare Your Data

1.  **Edit `data/domains.txt`**: Populate this file with the list of domains you want to process, one domain per line.
2.  **Review Configuration**: Open each script and review the default parameter values at the top. Adjust them if necessary (e.g., `AliasPassword`, `AliasCount`).

---

## Step 3: Execute the Automation Workflow

The workflow is divided into phases. Run the scripts in the following order.

### Phase 1: DNS & Verification

1.  **Pass 1-1: Enable Enhanced Protection**

    ```powershell
    .\Pass1-1-EnableEnhancedProtection.ps1
    ```

2.  **Pass 1-2: Update DNS Records**

    *(This step is manual or requires a separate script for your DNS provider, e.g., Cloudflare)*

3.  **Pass 1-3: Verify DNS Propagation**

    ```powershell
    .\Pass1-3-VerifyDNS.ps1
    ```

### Phase 2: Alias Creation

1.  **Pass 2-1: Create Aliases**

    ```powershell
    .\Pass2-1-CreateAliases.ps1
    ```

    *Note: This script no longer attempts to set passwords.*

### Phase 3: Password Management

This is the new, dedicated phase for handling passwords.

1.  **Pass 3-1: Diagnose Password Capability**

    Before setting passwords in bulk, run the diagnostic tool to identify the root cause of any potential issues.

    ```powershell
    .\Test-PasswordAPI.ps1
    ```

    Review the output carefully. If it fails, you must resolve the reported issues before proceeding.

2.  **Pass 3-2: Set Passwords**

    Once the diagnostic tool passes, you can set passwords for all aliases.

    ```powershell
    .\Pass3-2-SetPasswords.ps1
    ```

    **Recommended Flags**:
    -   For speed: `.\Pass3-2-SetPasswords.ps1 -Parallel -ThrottleLimit 10`
    -   To resume an interrupted run: `.\Pass3-2-SetPasswords.ps1 -Resume`

3.  **Pass 3-3: Verify Passwords**

    After the script completes, verify the results.

    ```powershell
    .\Pass3-3-VerifyPasswords.ps1
    ```

### Phase 4: Audit & Reporting

1.  **Pass 4-1: Full System Audit**

    Run a comprehensive audit to get a final report on the health of your email infrastructure.

    ```powershell
    .\Pass4-1-SystemAudit.ps1
    ```

---

## Reviewing Output and Logs

-   **Console Output**: Provides real-time progress and status.
-   **`logs/` directory**: Contains detailed, timestamped log files for each script run.
-   **`data/` directory**: Contains CSV and JSON reports with the results of each operation.

---

## Troubleshooting

If you encounter any issues, please refer to `TROUBLESHOOTING.md` for common problems and solutions.

Key steps:
1.  **Re-run `Validate-Environment.ps1`** to check for environmental issues.
2.  **Run `Test-PasswordAPI.ps1`** to diagnose API-specific problems.
3.  **Check the latest log file** in the `logs/` directory for detailed error messages.
4.  **Review the generated CSV reports** in the `data/` directory for a list of specific failures.
