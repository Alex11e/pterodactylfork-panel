<?php

namespace Pterodactyl\Services\Subdomains;

use Illuminate\Support\Facades\Http;
use Symfony\Component\HttpKernel\Exception\HttpException;

class CloudflareDns
{
    public function request(string $method, string $zone, string $path = '', array $data = []): array
    {
        abort_unless(preg_match('/^[a-f0-9]{32}$/D', $zone), 503, 'Invalid Cloudflare zone configuration.');
        $url = 'https://api.cloudflare.com/client/v4/zones/' . $zone . '/dns_records' . $path;
        try {
            // Never retry POST automatically: a timeout can follow a successful creation.
            $response = Http::withToken(config('subdomains.token'))->acceptJson()->connectTimeout(5)->timeout(15)
                ->send($method, $url, [$method === 'GET' ? 'query' : 'json' => $data]);
        } catch (\Illuminate\Http\Client\ConnectionException) {
            throw new HttpException(503, 'Cloudflare connection failed. Retry using Sync or Delete.');
        }
        if (!$response->successful() || $response->json('success') !== true) {
            // Cloudflare response bodies and request headers must not reach the client.
            throw new HttpException(503, 'Cloudflare DNS request failed. Check the zone and DNS token permissions.');
        }

        return $response->json();
    }

    public function find(string $zone, string $hostname): array
    {
        $response = $this->request('GET', $zone, '', ['name' => $hostname, 'per_page' => 100]);
        abort_if(($response['result_info']['total_count'] ?? 0) > 100, 409, 'Too many DNS records for this name.');

        return $response['result'];
    }

    public function ownedRecord(array $records, string $ownership): ?array
    {
        if (!$records) {
            return null;
        }
        abort_unless(count($records) === 1 && ($records[0]['comment'] ?? '') === 'alex-panel:' . $ownership
            && in_array($records[0]['type'], ['A', 'AAAA'], true), 409, 'This name has DNS records not owned by this server.');

        return $records[0];
    }

    public function removeOwned(string $zone, string $hostname, string $ownership): void
    {
        $owned = array_values(array_filter($this->find($zone, $hostname), fn ($record) => ($record['comment'] ?? '') === 'alex-panel:' . $ownership && in_array($record['type'], ['A', 'AAAA'], true)));
        abort_if(count($owned) > 1, 409, 'Duplicate ownership markers. Ask an administrator to inspect Cloudflare DNS.');
        if ($owned) {
            $this->request('DELETE', $zone, '/' . $owned[0]['id']);
        }
    }
}
