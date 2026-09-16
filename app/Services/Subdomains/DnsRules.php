<?php

namespace Pterodactyl\Services\Subdomains;

final class DnsRules
{
    public static function hostname(string $label, string $domain): string
    {
        $domain = strtolower($domain);
        $reserved = ['www', 'mail', 'smtp', 'imap', 'pop', 'ftp', 'api', 'admin', 'panel', 'wings', 'ns1', 'ns2', 'autodiscover'];
        if (!preg_match('/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/D', $label) || in_array($label, $reserved, true)) {
            throw new \InvalidArgumentException('Invalid or reserved subdomain label.');
        }
        if (!str_contains($domain, '.') || filter_var($domain, FILTER_VALIDATE_IP) || !filter_var($domain, FILTER_VALIDATE_DOMAIN, FILTER_FLAG_HOSTNAME) || strlen($label . '.' . $domain) > 253) {
            throw new \InvalidArgumentException('Invalid configured subdomain domain.');
        }

        return $label . '.' . $domain;
    }

    public static function recordType(string $ip): string
    {
        if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_GLOBAL_RANGE)
            || (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) && (int) explode('.', $ip)[0] >= 224)
            || str_starts_with(strtolower($ip), 'ff')) {
            throw new \InvalidArgumentException('The primary allocation must use a public IP address.');
        }

        return str_contains($ip, ':') ? 'AAAA' : 'A';
    }
}
