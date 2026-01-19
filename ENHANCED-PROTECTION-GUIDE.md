# Enhanced Protection Guide

## Overview

**Enhanced Protection** is a Forward Email feature that hides your email forwarding configuration from public DNS lookups by using cryptographically generated random strings instead of publicly visible TXT records.

## Benefits

- **Privacy**: Forwarding aliases are not visible to anyone performing DNS lookups
- **Security**: Uses cryptographic verification strings instead of predictable domain IDs
- **Professional**: Prevents competitors from discovering your email infrastructure
- **Compliance**: Helps meet privacy requirements by obscuring email routing

## Pricing

Enhanced Protection is a **paid feature** included in Forward Email's $3/month plan.

## How It Works

### Standard Configuration (Without Enhanced Protection)

```
TXT record: forward-email-site-verification=<domain_id>
```

The domain ID is predictable and publicly visible in DNS.

### Enhanced Protection Configuration

```
TXT record: forward-email-site-verification=XnmA4Q3ju6
```

A cryptographically generated random string that cannot be predicted or enumerated.

## Implementation in Scripts

### Correct Workflow Order

1. **Add domain to Forward Email**
2. **Enable Enhanced Protection** ← Must happen before DNS configuration
3. **Extract verification string** from API response
4. **Configure DNS records in Cloudflare** using the verification string
5. **Set all records to "DNS only"** (not proxied)
6. **Verify domain** after DNS propagation
7. **Create aliases**

### Phase 1: Domain Creation & Enhanced Protection

```powershell
# Add domain to Forward Email
$forwardEmailDomain = $forwardEmailClient.CreateDomain($domain)

# Enable Enhanced Protection immediately
$enhancedDomain = $forwardEmailClient.EnableEnhancedProtection($domain)

# Extract verification string
$verificationString = $enhancedDomain.verification_record
```

### Phase 2: DNS Configuration

```powershell
# Use Enhanced Protection verification string
$txtValue = "\"forward-email-site-verification=$verificationString\""

# Create TXT record with DNS-only mode (not proxied)
$txtRecord = $cloudflareClient.CreateOrUpdateDnsRecord(
    $zoneId, 
    $domain, 
    "TXT", 
    $txtValue, 
    3600,      # TTL: 60 minutes
    $null,     # No priority for TXT
    $false     # DNS only (not proxied)
)

# Create MX records with DNS-only mode
$mx1 = $cloudflareClient.CreateOrUpdateDnsRecord(
    $zoneId, 
    $domain, 
    "MX", 
    "mx1.forwardemail.net", 
    3600,      # TTL: 60 minutes
    10,        # Priority: 10
    $false     # DNS only (not proxied)
)

$mx2 = $cloudflareClient.CreateOrUpdateDnsRecord(
    $zoneId, 
    $domain, 
    "MX", 
    "mx2.forwardemail.net", 
    3600,      # TTL: 60 minutes
    10,        # Priority: 10 (both MX records use same priority)
    $false     # DNS only (not proxied)
)
```

## DNS Requirements

### Critical Settings

1. **Proxy Status**: All email-related records MUST be set to **"DNS only"** (not proxied)
   - TXT verification record
   - TXT catch-all forwarding record
   - MX records (mx1 and mx2)

2. **MX Priority**: Both MX records should use **priority 10** (per Forward Email documentation)

3. **TTL**: Set to **3600 seconds (60 minutes)** or as close as possible

### Why DNS Only?

Cloudflare's proxy feature:
- Intercepts HTTP/HTTPS traffic (ports 80/443)
- Does NOT work with email (port 25)
- Will **break email delivery** if enabled for MX records
- Cannot be used with TXT records for email verification

## API Response Structure

When you enable Enhanced Protection, the API returns:

```json
{
  "id": "domain_id_here",
  "name": "example.com",
  "has_enhanced_protection": true,
  "verification_record": "XnmA4Q3ju6",
  "has_mx_record": false,
  "has_txt_record": false,
  ...
}
```

The `verification_record` field contains the cryptographic string to use in your DNS TXT record.

## Script Usage

### Three-Phase Script (Recommended)

```powershell
# Run the full automation with Enhanced Protection
.\Setup-EmailInfrastructure-ThreePhase.ps1 -DomainsFile "data\domains.txt"
```

The script automatically:
1. Adds domains to Forward Email
2. Enables Enhanced Protection
3. Extracts verification strings
4. Configures DNS with DNS-only mode
5. Verifies domains
6. Creates aliases

### Standalone Phase 3 (After Manual Verification)

```powershell
# If you want to verify domains manually first
.\Phase3-AliasGeneration.ps1
```

## Verification

### Check Enhanced Protection Status

```powershell
# Get domain details
$domain = $forwardEmailClient.GetDomain("example.com")

# Check if Enhanced Protection is enabled
if ($domain.has_enhanced_protection) {
    Write-Host "Enhanced Protection: ENABLED" -ForegroundColor Green
    Write-Host "Verification String: $($domain.verification_record)"
} else {
    Write-Host "Enhanced Protection: DISABLED" -ForegroundColor Yellow
}
```

### Verify DNS Records in Cloudflare

```powershell
# List DNS records
$records = $cloudflareClient.ListDnsRecords($zoneId, "TXT", $domain)

foreach ($record in $records.result) {
    Write-Host "Type: $($record.type)"
    Write-Host "Name: $($record.name)"
    Write-Host "Content: $($record.content)"
    Write-Host "Proxied: $($record.proxied)"  # Should be FALSE
    Write-Host "TTL: $($record.ttl)"
    Write-Host ""
}
```

### Verify in Forward Email Dashboard

1. Go to https://forwardemail.net/my-account/domains
2. Find your domain
3. Check for green checkmarks:
   - ✅ MX records configured
   - ✅ TXT verification record found
   - 🔒 Enhanced Protection enabled

## Troubleshooting

### Issue: Domain verification fails

**Cause**: DNS records not propagated or incorrect proxy status

**Solution**:
1. Check DNS propagation: `nslookup -type=TXT example.com`
2. Verify proxy status is "DNS only" in Cloudflare
3. Wait 5-10 minutes for DNS propagation
4. Re-run verification

### Issue: Enhanced Protection not enabled

**Cause**: Account not on paid plan or API error

**Solution**:
1. Check Forward Email subscription status
2. Verify API key has correct permissions
3. Check script logs for error messages
4. Try enabling manually in dashboard first

### Issue: MX records show as proxied

**Cause**: Cloudflare API not setting proxied=false correctly

**Solution**:
1. Manually disable proxy in Cloudflare dashboard
2. Verify script is passing `$false` for proxied parameter
3. Check CloudflareClient module version

## Best Practices

1. **Always enable Enhanced Protection** before configuring DNS
2. **Use DNS-only mode** for all email-related records
3. **Set TTL to 3600** (60 minutes) for faster propagation
4. **Wait for DNS propagation** before verification (3-5 minutes minimum)
5. **Verify in dashboard** before creating aliases
6. **Keep API keys secure** - Enhanced Protection requires paid account

## Migration from Standard to Enhanced Protection

If you have existing domains without Enhanced Protection:

```powershell
# Enable Enhanced Protection for existing domain
$enhancedDomain = $forwardEmailClient.EnableEnhancedProtection("example.com")

# Update TXT record with new verification string
$verificationString = $enhancedDomain.verification_record
$txtValue = "\"forward-email-site-verification=$verificationString\""

# Update DNS record
$cloudflareClient.UpdateDnsRecord($zoneId, $recordId, @{
    content = $txtValue
    proxied = $false
})
```

## References

- [Forward Email API Documentation](https://forwardemail.net/en/api)
- [Enhanced Protection Feature](https://forwardemail.net/en/faq#enhanced-protection)
- [Cloudflare DNS API](https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-create-dns-record)
- [MX Record Configuration](https://forwardemail.net/en/faq#how-do-i-get-started-and-set-up-email-forwarding)

## Support

For issues or questions:
- GitHub Issues: https://github.com/steadycalls/DU-email-infra-powershell/issues
- Forward Email Support: https://forwardemail.net/en/help
- Cloudflare Support: https://support.cloudflare.com/

---

**Last Updated**: January 19, 2026  
**Script Version**: 3.0 (Enhanced Protection Support)
