<?php

namespace Pterodactyl\Services\Nodes;

use InvalidArgumentException;

/** Browser-facing Wings origin; deliberately separate from the daemon API/JWT audience. */
class PublicEndpoint
{
    public static function resolve(int $nodeId, string $fallback, array $endpoints, bool $securePanel): string
    {
        if (!array_key_exists($nodeId, $endpoints)) {
            return $fallback;
        }

        $url = $endpoints[$nodeId];
        if (!is_string($url) || preg_match('/[\s\\\\]/', $url)) {
            throw new InvalidArgumentException("Invalid public Wings URL for node {$nodeId}.");
        }

        $parts = parse_url($url);
        if ($parts === false || !in_array($parts['scheme'] ?? '', ['http', 'https'], true)
            || empty($parts['host']) || filter_var($url, FILTER_VALIDATE_URL) === false
            || isset($parts['user']) || isset($parts['pass']) || isset($parts['query']) || isset($parts['fragment'])
            || !in_array($parts['path'] ?? '', ['', '/'], true)
            || (isset($parts['port']) && $parts['port'] < 1)) {
            throw new InvalidArgumentException("Public Wings URL for node {$nodeId} must be an HTTP(S) origin without credentials, path, query or fragment.");
        }

        if ($securePanel && $parts['scheme'] !== 'https') {
            throw new InvalidArgumentException("Node {$nodeId} requires a public HTTPS URL because the panel uses HTTPS.");
        }

        return rtrim($url, '/');
    }
}
