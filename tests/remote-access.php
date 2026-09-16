<?php

// Dependency-free regression suite: php tests/remote-access.php
require __DIR__ . '/../app/Services/Nodes/PublicEndpoint.php';

use Pterodactyl\Services\Nodes\PublicEndpoint;

$passed = 0;
$check = function (bool $condition, string $description) use (&$passed): void {
    if (!$condition) {
        throw new RuntimeException($description);
    }
    ++$passed;
};

$fallback = 'http://10.0.0.5:8080';
$check(PublicEndpoint::resolve(1, $fallback, [], true) === $fallback, 'Unset override must preserve existing behavior');
$check(PublicEndpoint::resolve(2, $fallback, [1 => 'https://node.example.com'], true) === $fallback, 'Do not leak another node override');
foreach (['https://node.example.com', 'https://node.example.com:8443', 'https://[2001:db8::1]:8443', 'https://203.0.113.10:8443'] as $url) {
    $check(PublicEndpoint::resolve(1, $fallback, [1 => $url . '/'], true) === $url, 'Valid public origin: ' . $url);
}
$check(PublicEndpoint::resolve(1, $fallback, [1 => 'http://localhost:8080'], false) === 'http://localhost:8080', 'HTTP development support');
$mapping = json_decode('{"1":"https://one.example.com","2":"https://two.example.com"}', true, 512, JSON_THROW_ON_ERROR);
$check(PublicEndpoint::resolve(2, $fallback, $mapping, true) === 'https://two.example.com', 'JSON environment mapping');

foreach ([null, 123, [], '', 'javascript:alert(1)', '//node.example.com', 'wss://node.example.com',
    'https://user:secret@node.example.com', 'https://node.example.com/path', 'https://node.example.com//',
    'https://node.example.com?token=secret', 'https://node.example.com#fragment', 'https://node.example.com:0',
    'https://node.example.com:99999', "https://node.example.com\n", 'https://node.example.com\\@evil.example.com',
    'http://node.example.com', 'https:///missing-host', ' https://node.example.com'] as $invalid) {
    try {
        PublicEndpoint::resolve(1, $fallback, [1 => $invalid], true);
    } catch (InvalidArgumentException) {
        ++$passed;
        continue;
    }
    throw new RuntimeException('Accepted invalid or mixed-content origin: ' . json_encode($invalid));
}

echo "PASS: {$passed} remote-access regression checks\n";
