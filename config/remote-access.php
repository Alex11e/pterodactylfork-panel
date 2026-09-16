<?php

return [
    // proxy: browser -> panel nginx -> private Wings. direct: legacy public Wings.
    'mode' => env('WINGS_BROWSER_MODE', 'direct'),
    // Node ID => public Wings HTTP(S) origin. No server-supplied or request-supplied hosts.
    // Example .env: WINGS_PUBLIC_URLS='{"1":"https://node.example.com"}'
    'public_urls' => json_decode(env('WINGS_PUBLIC_URLS', '{}'), true, 512, JSON_THROW_ON_ERROR),
];
