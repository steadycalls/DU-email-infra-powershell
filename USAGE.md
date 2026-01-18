# Usage Guide

This guide provides detailed examples of how to use the `Setup-EmailInfrastructure.ps1` script.

## Basic Usage

The most common use case is to run the script with a specified domains file. The script will use the configuration from environment variables and default settings.

```powershell
.\Setup-EmailInfrastructure.ps1 -DomainsFile path\to\your\domains.txt
```

## Advanced Usage

### Specifying Log Level

To get more detailed output for debugging, you can set the log level to `DEBUG`.

```powershell
.\Setup-EmailInfrastructure.ps1 -DomainsFile data\domains.txt -LogLevel DEBUG
```

### Adjusting Concurrency

To process more domains in parallel, you can increase the concurrency limit. Be mindful of API rate limits.

```powershell
.\Setup-EmailInfrastructure.ps1 -DomainsFile data\domains.txt -ConcurrentDomains 10
```

### Using a Custom Configuration File

You can override default settings and environment variables by providing a JSON configuration file. This is useful for managing different environments or alias setups.

```powershell
.\Setup-EmailInfrastructure.ps1 -DomainsFile data\domains.txt -ConfigFile config\production.json
```

See `examples/config-example.json` for the structure of the configuration file.

### Dry Run Mode

To see what the script would do without making any actual changes to your Forward Email or Cloudflare accounts, use the `-DryRun` switch.

```powershell
.\Setup-EmailInfrastructure.ps1 -DomainsFile data\domains.txt -DryRun
```

This is a safe way to validate your input file and configuration before execution.

### Resuming from a Previous Run

The script automatically saves its state to a JSON file (default: `data/state.json`). If the script is interrupted, you can simply run it again with the same command. It will load the state file and resume processing only the domains that are not yet in a `Completed` or `Failed` state.

```powershell
# If this run is interrupted...
.\Setup-EmailInfrastructure.ps1 -DomainsFile data\domains.txt

# ...you can just run it again to resume
.\Setup-EmailInfrastructure.ps1 -DomainsFile data\domains.txt
```

### Handling Failures

After a run, any domains that failed will be listed in the summary output. A detailed report of these failures is saved to `data/failures.json` (or the path specified by `FailuresFile` in your config).

You can review this file to understand why each domain failed. After correcting the underlying issues (e.g., adding the domain to Cloudflare, fixing a typo), you can either:

1.  **Retry the failed domains**: Create a new domains file containing only the failed domains and run the script again.
2.  **Reset the state**: For a specific domain, you can manually edit the `state.json` file, change its state from `Failed` back to `Pending`, and re-run the script.

## Script Parameters

Here is a complete list of the command-line parameters for `Setup-EmailInfrastructure.ps1`:

| Parameter           | Type     | Description                                                                 | Default Value                |
| ------------------- | -------- | --------------------------------------------------------------------------- | ---------------------------- |
| `-DomainsFile`      | `string` | Path to the input domains file.                                             | `data/domains.txt`           |
| `-ConfigFile`       | `string` | Optional path to a JSON configuration file.                                 | `null`                       |
| `-StateFile`        | `string` | Path for the state persistence file.                                        | `data/state.json`            |
| `-LogFile`          | `string` | Path for the log file.                                                      | `logs/automation.log`        |
| `-LogLevel`         | `string` | Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL).                      | `INFO`                       |
| `-ConcurrentDomains`| `int`    | Number of domains to process in parallel.                                   | `5`                          |
| `-DryRun`           | `switch` | If specified, performs validation only without making any API calls.        | `$false`                     |
