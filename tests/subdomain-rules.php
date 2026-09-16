<?php

require __DIR__ . '/../app/Services/Subdomains/DnsRules.php';

use Pterodactyl\Services\Subdomains\DnsRules;

$checks = 0;
function check(bool $condition): void
{
    global $checks;
    ++$checks;
    if (!$condition) {
        throw new RuntimeException('Check failed: ' . $checks);
    }
}
function rejected(callable $callback): void
{
    try {
        $callback();
    } catch (InvalidArgumentException) {
        check(true);

        return;
    }
    check(false);
}
check(DnsRules::hostname('survival', 'games.example.com') === 'survival.games.example.com');
check(DnsRules::hostname('a', 'EXAMPLE.COM') === 'a.example.com');
check(DnsRules::hostname(str_repeat('a', 63), 'example.com') === str_repeat('a', 63) . '.example.com');
foreach (['', '-a', 'a-', 'a.b', '*', '../a', 'a/b', 'a b', 'a_b', 'www', 'panel', 'wings', str_repeat('a', 64)] as $label) {
    rejected(fn () => DnsRules::hostname($label, 'example.com'));
}
foreach (['localhost', 'https://example.com', 'example.com/path', '*.example.com', '127.0.0.1', 'example..com'] as $domain) {
    rejected(fn () => DnsRules::hostname('game', $domain));
}
foreach (['127.0.0.1', '0.0.0.0', '10.0.0.1', '192.168.1.1', '172.16.0.1', '169.254.1.1', '100.64.0.1', '224.0.0.1', 'ff02::1', '::1', 'fc00::1', 'fe80::1', 'not-an-ip'] as $ip) {
    rejected(fn () => DnsRules::recordType($ip));
}
check(DnsRules::recordType('8.8.8.8') === 'A');
check(DnsRules::recordType('2606:4700:4700::1111') === 'AAAA');
echo "Subdomain rules: $checks checks passed.\n";
