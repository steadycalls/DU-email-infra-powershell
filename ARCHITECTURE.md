# Architecture Documentation

This document provides a detailed technical overview of the Email Infrastructure Automation system architecture, design decisions, and implementation details.

## System Overview

The Email Infrastructure Automation system is a PowerShell 7-based solution designed to automate the complete lifecycle of email infrastructure provisioning for bulk domain portfolios. It orchestrates interactions between Forward Email (for email forwarding services) and Cloudflare (for DNS management) to transform a simple list of domains into fully operational email-forwarding assets.

The architecture prioritizes **reliability**, **observability**, **idempotency**, and **recovery from partial failures**. Every operation is designed to be safely retried, and the system maintains comprehensive state tracking to enable interruption and resumption without data loss or duplicate operations.

## Core Design Principles

### Idempotency

All operations are designed to be idempotent, meaning they can be executed multiple times without causing unintended side effects. Before creating resources (domains, DNS records, aliases), the system checks if they already exist. This allows the script to be safely re-run on the same domain list without causing conflicts or duplicates.

### State Persistence

The system maintains a persistent state file that tracks the progress of each domain through the processing pipeline. This state is saved after every significant operation, ensuring that if the script is interrupted (by user action, system failure, or network issues), it can be restarted and will resume from the last successful checkpoint for each domain.

### Defensive Programming

The system assumes that external APIs may fail, DNS propagation takes time, and rate limits exist. All API calls are wrapped in retry logic with exponential backoff. Transient errors (network timeouts, rate limiting, server errors) trigger automatic retries, while permanent errors (authentication failures, resource not found) are immediately flagged and logged.

### Explicit Failure Tracking

Domains that fail are not silently dropped or lost. Each failure is recorded with a specific error code, message, timestamp, and contextual information. Failed domains are tracked in the state file and exported to a separate failures report for manual review and remediation.

### Separation of Concerns

The system is organized into distinct modules, each responsible for a specific aspect of functionality. This modular design improves maintainability, testability, and allows for independent evolution of components.

## Component Architecture

The system consists of five primary layers:

### 1. Configuration Layer (`Config.psm1`)

The configuration layer provides a centralized, type-safe configuration object that loads settings from environment variables, optional JSON configuration files, and command-line parameters. It defines all operational parameters including API credentials, retry behavior, verification timeouts, concurrency limits, and alias definitions.

**Key Features:**
- Environment variable loading with fallback to default values
- JSON configuration file support for environment-specific settings
- Validation of required credentials
- Type-safe configuration with PowerShell classes

### 2. State Management Layer (`StateManager.psm1`)

The state management layer implements a persistent state machine for tracking domain processing. It uses a JSON file as the backing store and provides thread-safe access through mutex locks.

**State Machine:**
Each domain progresses through the following states:

1.  **Pending**: Initial state when loaded from input file
2.  **ForwardEmailAdded**: Domain successfully added to Forward Email
3.  **DnsConfigured**: Required DNS records created in Cloudflare
4.  **Verifying**: Actively polling for DNS verification
5.  **Verified**: Domain verified by Forward Email
6.  **AliasesCreated**: Email aliases successfully created
7.  **Completed**: Full pipeline successful
8.  **Failed**: Unrecoverable error occurred

**Key Features:**
- Atomic file writes (write to temp file, then rename)
- Thread-safe operations with mutex locks
- Automatic backup of corrupted state files
- Rich error tracking with timestamps and context
- Summary statistics and failure export

### 3. API Client Layer

The API client layer provides abstracted, retry-aware interfaces to external services.

#### Forward Email Client (`ForwardEmailClient.psm1`)

Implements the Forward Email REST API with methods for:
- Domain management (create, retrieve, list, verify)
- Alias management (create, list)
- Existence checking (idempotent operations)

**Authentication:** HTTP Basic Auth with API key as username, empty password.

#### Cloudflare Client (`CloudflareClient.psm1`)

Implements the Cloudflare REST API with methods for:
- Zone management (list, get zone ID)
- DNS record management (create, list, update, delete)
- Idempotent record creation (get-or-create pattern)

**Authentication:** Bearer token in Authorization header.

**Both clients implement:**
- Exponential backoff with jitter for transient failures
- Automatic rate limit handling (HTTP 429)
- Configurable retry limits and delays
- Detailed error logging

### 4. Logging Layer (`Logger.psm1`)

The logging layer provides structured, thread-safe logging to both console and file. It supports multiple log levels (DEBUG, INFO, WARNING, ERROR, CRITICAL) with color-coded console output and JSON-formatted file output.

**Key Features:**
- Structured logging with domain and context fields
- Thread-safe file writes
- Configurable minimum log level
- Color-coded console output for readability

### 5. Orchestration Layer (`Setup-EmailInfrastructure.ps1`)

The orchestration layer is the main entry point that coordinates all other components. It implements the core business logic of the domain processing pipeline.

**Processing Flow:**

For each domain, the orchestrator:

1.  **Loads or creates domain record** from state manager
2.  **Checks if already completed** and skips if so
3.  **Adds domain to Forward Email** (if in Pending state)
4.  **Retrieves Cloudflare Zone ID** for the domain
5.  **Creates DNS records** (verification TXT, MX records)
6.  **Polls for verification** with exponential backoff
7.  **Creates email aliases** once verified
8.  **Marks domain as completed** and saves state

**Concurrency Model:**

The orchestrator uses PowerShell background jobs to process multiple domains concurrently. A configurable concurrency limit prevents overwhelming the APIs or exhausting system resources. The orchestrator monitors job completion and maintains the concurrency limit by starting new jobs as others complete.

## Data Flow

The typical successful flow for a single domain:

```
Input File → State Manager (Pending)
    ↓
Forward Email API (Create Domain)
    ↓
State Manager (ForwardEmailAdded)
    ↓
Cloudflare API (Get Zone ID)
    ↓
Cloudflare API (Create DNS Records)
    ↓
State Manager (DnsConfigured)
    ↓
Forward Email API (Verify Domain) [Polling Loop]
    ↓
State Manager (Verified)
    ↓
Forward Email API (Create Aliases)
    ↓
State Manager (Completed)
```

At each step, the state is persisted before moving to the next step. If an error occurs, the domain is marked as Failed with detailed error information.

## Error Handling Strategy

### Transient Errors

Errors that are expected to resolve with time or retries:
- Network timeouts
- Rate limiting (HTTP 429)
- Server errors (HTTP 5xx)

**Handling:** Exponential backoff retry with configurable maximum attempts.

### Permanent Errors

Errors that indicate a fundamental problem:
- Invalid credentials (HTTP 401)
- Insufficient permissions (HTTP 403)
- Resource not found (HTTP 404)
- Resource already exists (HTTP 409)

**Handling:** Immediate failure, no retry. Error is logged with full context.

### DNS Propagation Timeout

If verification polling exceeds the maximum attempts:

**Handling:** Domain marked as Failed with timeout error. Can be manually retried after DNS propagation completes.

### Partial Success Recovery

If a domain fails mid-pipeline (e.g., DNS configured but verification times out), the state file preserves all completed steps. On restart, the system resumes from the last successful state rather than repeating completed operations.

## Retry and Backoff Logic

The system implements exponential backoff with jitter:

```
delay = min(initial_delay * (2 ^ attempt), max_delay) + random(0, 5)
```

This prevents thundering herd problems when multiple domains hit rate limits simultaneously and ensures graceful backoff under API pressure.

## Security Considerations

### API Key Storage

API keys and tokens are stored in environment variables or configuration files, never hardcoded in scripts. The `.env.example` file provides a template, and the actual `.env` file should be excluded from version control.

### State File Permissions

The state file contains domain IDs and configuration details. It should be protected with appropriate file system permissions to prevent unauthorized access.

### Log Sanitization

API keys and sensitive data are not logged. Only sanitized request/response information is included in logs.

### HTTPS Only

All API communication uses HTTPS with certificate validation enabled by default in PowerShell's `Invoke-RestMethod`.

## Scalability Considerations

The system is designed to handle hundreds to thousands of domains:

- **Stateless Workers**: Each domain is processed independently, enabling horizontal scaling
- **Persistent State**: State file enables pause/resume and distributed processing
- **Rate Limit Awareness**: Built-in backoff prevents API quota exhaustion
- **Concurrency Control**: Configurable parallelism balances throughput with resource constraints
- **Incremental Processing**: Domains can be added to the input file over time and processed incrementally

## Future Enhancements

Potential areas for future development:

- **Database Backend**: Replace JSON state file with a database (PostgreSQL, SQLite) for better concurrency and querying
- **Web Dashboard**: Build a web interface for monitoring progress and managing domains
- **Webhook Integration**: Add webhook notifications for domain completion/failure
- **Bulk Alias Management**: Support for updating aliases across all domains
- **DNS Record Validation**: Pre-flight checks to validate DNS configuration before processing
- **Multi-Account Support**: Handle multiple Forward Email and Cloudflare accounts in a single run
