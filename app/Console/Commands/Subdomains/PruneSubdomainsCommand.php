<?php

namespace Pterodactyl\Console\Commands\Subdomains;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;
use Pterodactyl\Services\Subdomains\CloudflareDns;

class PruneSubdomainsCommand extends Command
{
    protected $signature = 'p:subdomains:prune {--delete : Delete orphan DNS records; otherwise only list them}';
    protected $description = 'List or remove subdomains left behind by deleted game servers.';

    public function handle(CloudflareDns $dns): int
    {
        $lock = Cache::lock('alex-panel:subdomains', 120);
        if (!$lock->get()) {
            $this->error('Another DNS operation is in progress.');

            return 1;
        }
        try {
            // One orphan per invocation bounds API time below the shared lock lifetime.
            if (!$this->option('delete')) {
                $this->table(['Hostname', 'Zone', 'Status'], DB::table('server_subdomains')->whereNull('server_id')
                    ->get(['hostname', 'zone_id', 'status'])->map(fn ($row) => (array) $row)->all());

                return 0;
            }
            if (!config('subdomains.token')) {
                $this->error('Configure CLOUDFLARE_DNS_TOKEN first.');

                return 1;
            }
            $row = DB::table('server_subdomains')->whereNull('server_id')->orderBy('id')->first();
            if ($row) {
                $dns->removeOwned($row->zone_id, $row->hostname, $row->ownership);
                DB::table('server_subdomains')->where('id', $row->id)->delete();
                $this->info('Removed: ' . $row->hostname . '. Run again for the next orphan.');
            } else {
                $this->info('No orphan subdomains.');
            }

            return 0;
        } finally {
            $lock->release();
        }
    }
}
