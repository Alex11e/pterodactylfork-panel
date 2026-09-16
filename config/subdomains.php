<?php

return [
    'enabled' => env('SUBDOMAINS_ENABLED', false),
    'domain' => env('SUBDOMAINS_DOMAIN', ''),
    'zone_id' => env('CLOUDFLARE_ZONE_ID', ''),
    'token' => env('CLOUDFLARE_DNS_TOKEN', ''),
];
