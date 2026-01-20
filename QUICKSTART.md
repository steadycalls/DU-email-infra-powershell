# Quick Start Guide

Get up and running with the new email infrastructure automation in 5 steps.

---

## Step 1: Validate Your Environment

```powershell
.\Validate-Environment.ps1
```

**Expected Result**: `STATUS: READY` or `STATUS: READY WITH WARNINGS`

If you see `STATUS: FAILED`, fix the reported issues before proceeding.

---

## Step 2: Diagnose Password API

```powershell
.\Test-PasswordAPI.ps1
```

**Expected Result**: All tests pass, or warnings with actionable recommendations.

If tests fail, review the error messages and follow the recommendations. Common issues:

-   **403 Forbidden**: Your plan may not support IMAP/passwords. Upgrade to Enhanced Protection.
-   **401 Unauthorized**: API key is invalid or expired. Check your API key.
-   **400 Bad Request**: Alias configuration may not support passwords. Check alias type.

---

## Step 3: Set Passwords for All Aliases

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

---

## Step 4: Review Results

Check the output files in the `data/` directory:

-   `pass3-2-password-results.csv`: List of failed aliases with error details
-   `pass3-2-summary.json`: Execution summary with success rate

**Success Rate ≥ 95%**: Excellent! Proceed to verification.  
**Success Rate 80-95%**: Good, but review failures and consider re-running.  
**Success Rate < 80%**: Investigate the root cause using the CSV report.

---

## Step 5: Verify and Export

Run the export script to generate a fresh report:

```powershell
.\Export-Aliases.ps1
```

Check the `HasPassword` column in the exported CSV. It should now show `True` for most aliases (excluding catch-all aliases).

---

## Troubleshooting

If you encounter issues:

1.  **Re-run `Test-PasswordAPI.ps1`** to diagnose API-specific problems.
2.  **Check the log files** in the `logs/` directory for detailed error messages.
3.  **Review the CSV reports** in the `data/` directory for specific failures.
4.  **Consult `TROUBLESHOOTING.md`** for common issues and solutions.

---

## Next Steps

-   **Update existing scripts**: Remove password-setting logic from `Pass2-AliasCreation.ps1`.
-   **Integrate Phase 3**: Add the new password phase to your overall workflow.
-   **Monitor and iterate**: Run the workflow on a small subset first, then scale up.
