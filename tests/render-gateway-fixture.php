<?php

// Used by the real nginx HTTP/WebSocket test harness with ephemeral loopback ports.
require __DIR__ . '/../app/Services/Nodes/PublicEndpoint.php';
require __DIR__ . '/../app/Services/Nodes/NginxGateway.php';

echo \Pterodactyl\Services\Nodes\NginxGateway::render([
    1 => 'http://127.0.0.1:' . (int) $argv[1],
    2 => 'http://127.0.0.1:' . (int) $argv[2],
]);
