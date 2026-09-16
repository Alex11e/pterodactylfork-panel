<?php

namespace Pterodactyl\Console\Commands\Server;

use Pterodactyl\Models\Node;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;

class RemoteAccessCommand extends Command
{
    protected $signature = 'p:remote-access:check {node : Numeric node ID} {--probe : Check the public HTTPS endpoint from this panel host}';

    protected $description = 'Show internal/public Wings addresses and detect common remote access configuration errors.';

    public function handle(): int
    {
        $id = (string) $this->argument('node');
        if (!ctype_digit($id) || !($node = Node::find((int) $id))) {
            $this->error('Node not found. Supply its numeric ID from the admin panel.');

            return self::FAILURE;
        }

        try {
            $public = $node->getPublicConnectionAddress();
        } catch (\InvalidArgumentException|\TypeError $exception) {
            $this->error($exception->getMessage());

            return self::FAILURE;
        }

        $this->table(['Purpose', 'Address'], [
            ['Panel to Wings', $node->getConnectionAddress()],
            ['Browser endpoint (' . config('remote-access.mode', 'direct') . ')', $public],
            ['Browser WebSocket', str_replace(['https://', 'http://'], ['wss://', 'ws://'], $public) . '/api/servers/{uuid}/ws'],
            ['Allowed browser Origin', config('app.url')],
        ]);

        if (str_starts_with(config('app.url', ''), 'https://') && !str_starts_with($public, 'https://')) {
            $this->error('HTTPS panel + HTTP Wings causes browser mixed-content blocking. Configure a public HTTPS Wings origin.');

            return self::FAILURE;
        }

        $this->line('Wings remote/allowed_origins must include the panel origin, not your home/mobile IP.');
        $this->line('SFTP and game ports are separate TCP/UDP services and require their own routing.');

        if ($this->option('probe')) {
            try {
                // Never send a daemon token; never follow a redirect to another host.
                $proxy = config('remote-access.mode') === 'proxy';
                $response = Http::connectTimeout(5)->timeout(10)->withoutRedirecting()
                    ->send($proxy ? 'OPTIONS' : 'GET', $public . ($proxy ? '/download/file' : '/api/system'));
                $expected = $proxy ? 204 : 401;
                if ($response->status() !== $expected || ($proxy && !$response->header('Access-Control-Allow-Origin'))) {
                    $this->error('Unexpected probe response: HTTP ' . $response->status() . '. Check the gateway include, upstream and Wings.');

                    return self::FAILURE;
                }
                $this->info('Endpoint reachable; expected unauthenticated response received. This does not verify WebSocket or external-client connectivity.');
            } catch (\Illuminate\Http\Client\ConnectionException $exception) {
                $this->error('Public endpoint connection failed. Check DNS, TLS, listening port, firewall and NAT.');

                return self::FAILURE;
            }
        }

        return self::SUCCESS;
    }
}
