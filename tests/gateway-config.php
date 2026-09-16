<?php

require __DIR__ . '/../app/Services/Nodes/PublicEndpoint.php';
require __DIR__ . '/../app/Services/Nodes/NginxGateway.php';

use Pterodactyl\Services\Nodes\NginxGateway;

$count = 0;
$check = function (bool $condition) use (&$count): void {
    if (!$condition) {
        throw new RuntimeException('Gateway regression failure at check ' . ($count + 1));
    }
    ++$count;
};
$check(NginxGateway::browserAddress(12, 'https://panel.example.com/') === 'https://panel.example.com/_wings/12');
$check(NginxGateway::browserAddress(2, 'http://localhost:8080') === 'http://localhost:8080/_wings/2');
$nginx = NginxGateway::render([2 => 'https://node.internal:8443', 1 => 'http://127.0.0.1:8080']);
foreach (['location ^~ /_wings/ { return 404; }', 'proxy_pass http://127.0.0.1:8080;',
    'proxy_pass https://node.internal:8443;', 'proxy_ssl_verify on;', 'proxy_ssl_server_name on;',
    'proxy_set_header Cookie "";', 'proxy_set_header Authorization "";', 'proxy_hide_header Set-Cookie;',
    'proxy_set_header Origin $http_origin;', 'proxy_cache off;', 'access_log off;', "sandbox; default-src 'none'"] as $required) {
    $check(str_contains($nginx, $required));
}
foreach ([[-1 => 'http://localhost'], ['bad' => 'http://localhost'], [1 => 'http://localhost/a'],
    [1 => 'http://localhost;evil'], [1 => 'http://$host'], [1 => 'http://localhost#evil'],
    [1 => "http://localhost\n}"], [1 => 'http://name_with_underscore']] as $bad) {
    try {
        NginxGateway::render($bad);
    } catch (InvalidArgumentException) {
        ++$count;
        continue;
    }
    throw new RuntimeException('Accepted unsafe gateway input');
}
echo "PASS: {$count} gateway config checks\n";
