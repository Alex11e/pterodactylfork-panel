<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Illuminate\Support\Str;
use Pterodactyl\Models\Server;
use Pterodactyl\Facades\Activity;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;
use Pterodactyl\Services\Subdomains\DnsRules;
use Illuminate\Validation\ValidationException;
use Pterodactyl\Services\Subdomains\CloudflareDns;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\Network\GetNetworkRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Network\ManageSubdomainRequest;

class SubdomainController extends ClientApiController
{
    public function index(GetNetworkRequest $request, Server $server): array
    {
        $row = DB::table('server_subdomains')->where('server_id', $server->id)->first();

        return [
            'enabled' => (bool) config('subdomains.enabled'),
            'domain' => config('subdomains.domain'),
            'can_manage' => $request->user()->root_admin || $request->user()->id === $server->owner_id,
            'record' => $row ? ['hostname' => $row->hostname, 'ip' => $row->ip, 'port' => $row->port, 'status' => $row->status] : null,
        ];
    }

    public function save(ManageSubdomainRequest $request, Server $server, CloudflareDns $dns): array
    {
        $this->configured();

        return $this->locked(function () use ($request, $server, $dns) {
            $row = DB::table('server_subdomains')->where('server_id', $server->id)->first();
            abort_if($request->isMethod('POST') && $row, 409, 'Delete the existing subdomain before choosing a new name.');
            abort_if(!$request->isMethod('POST') && !$row, 404);
            try {
                $type = DnsRules::recordType($server->allocation->ip);
                $hostname = $row?->hostname ?? DnsRules::hostname($request->input('label'), config('subdomains.domain'));
            } catch (\InvalidArgumentException $exception) {
                throw ValidationException::withMessages(['label' => $exception->getMessage()]);
            }
            if (!$row) {
                abort_if(DB::table('server_subdomains')->where('hostname', $hostname)->exists(), 409, 'Subdomain is already reserved.');
                // Reserve before contacting the provider. A lost HTTP response must be recoverable.
                $id = DB::table('server_subdomains')->insertGetId([
                    'server_id' => $server->id, 'hostname' => $hostname, 'zone_id' => config('subdomains.zone_id'),
                    'ownership' => (string) Str::uuid(), 'ip' => $server->allocation->ip, 'port' => $server->allocation->port,
                    'status' => 'pending', 'created_at' => now(), 'updated_at' => now(),
                ]);
                $row = DB::table('server_subdomains')->where('id', $id)->first();
            }
            DB::table('server_subdomains')->where('id', $row->id)->update(['status' => 'pending', 'updated_at' => now()]);
            $record = $dns->ownedRecord($dns->find($row->zone_id, $hostname), $row->ownership);
            $dns->request($record ? 'PUT' : 'POST', $row->zone_id, $record ? '/' . $record['id'] : '', [
                'type' => $type, 'name' => $hostname, 'content' => $server->allocation->ip,
                'ttl' => 120, 'proxied' => false, 'comment' => 'alex-panel:' . $row->ownership,
            ]);
            DB::table('server_subdomains')->where('id', $row->id)->update([
                'status' => 'active', 'ip' => $server->allocation->ip, 'port' => $server->allocation->port, 'updated_at' => now(),
            ]);
            Activity::event('server:subdomain.sync')->property('hostname', $hostname)->log();

            return ['success' => true];
        });
    }

    public function delete(ManageSubdomainRequest $request, Server $server, CloudflareDns $dns): array
    {
        $this->configured();

        return $this->locked(function () use ($server, $dns) {
            $row = DB::table('server_subdomains')->where('server_id', $server->id)->first();
            if ($row) {
                // Only delete records with our persistent ownership marker, even after a lost POST response.
                $dns->removeOwned($row->zone_id, $row->hostname, $row->ownership);
                DB::table('server_subdomains')->where('id', $row->id)->delete();
                Activity::event('server:subdomain.delete')->property('hostname', $row->hostname)->log();
            }

            return ['success' => true];
        });
    }

    private function configured(): void
    {
        abort_unless(config('subdomains.enabled') && config('subdomains.token') && config('subdomains.zone_id'), 503, 'Subdomain manager is not configured.');
    }

    private function locked(\Closure $callback): array
    {
        // Shared Redis/file cache lock prevents two requests claiming the same name.
        $lock = Cache::lock('alex-panel:subdomains', 120);
        abort_unless($lock->get(), 409, 'Another DNS change is in progress. Please retry.');
        try {
            return $callback();
        } finally {
            $lock->release();
        }
    }
}
