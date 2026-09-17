<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Throwable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;
use Illuminate\Contracts\View\View;
use Pterodactyl\Models\Node;
use Pterodactyl\Http\Controllers\Controller;

class SystemStatusController extends Controller
{
    public function index(): View
    {
        $appUrl = (string) config('app.url');
        $host = parse_url($appUrl, PHP_URL_HOST) ?: '';
        $nodeCount = null;
        try {
            $nodeCount = Node::query()->count();
        } catch (Throwable $exception) {
            report($exception);
        }

        return view('admin.system-status', [
            'checks' => [
                'database' => $this->checkDatabase(),
                'cache' => $this->checkCache(),
                'queue' => [
                    'state' => 'info',
                    'label' => (string) config('queue.default'),
                    'detail' => 'A queue worker futását a telepítő diagnosztikája ellenőrzi.',
                ],
            ],
            'deployment' => [
                'version' => (string) config('app.version'),
                'url' => $appUrl,
                'host' => $host,
                'backend' => (string) config('pterodactyl.deployment.backend', 'unknown'),
                'bind_address' => (string) config('pterodactyl.deployment.bind_ip', 'unknown'),
                'tunnel_hostname' => (string) (config('pterodactyl.deployment.tunnel_hostname') ?: 'Nincs beállítva'),
                'nodes' => $nodeCount === null ? 'Nem elérhető' : $nodeCount,
            ],
            'security' => [
                'debug' => (bool) config('app.debug'),
                'https' => str_starts_with($appUrl, 'https://'),
                'localhost_origin' => in_array($host, ['localhost', '127.0.0.1', '::1'], true),
                'trusted_proxies' => config('trustedproxies.proxies'),
            ],
        ]);
    }

    private function checkDatabase(): array
    {
        try {
            DB::connection()->select('select 1');

            return ['state' => 'ok', 'label' => 'Elérhető', 'detail' => config('database.default')];
        } catch (Throwable $exception) {
            report($exception);

            return ['state' => 'error', 'label' => 'Nem elérhető', 'detail' => 'Ellenőrizd az adatbázis szolgáltatást és a naplót.'];
        }
    }

    private function checkCache(): array
    {
        try {
            $key = 'alex-panel:health-check';
            Cache::put($key, 'ok', now()->addMinute());
            $available = Cache::get($key) === 'ok';
            Cache::forget($key);

            return $available
                ? ['state' => 'ok', 'label' => 'Elérhető', 'detail' => config('cache.default')]
                : ['state' => 'error', 'label' => 'Nem írható', 'detail' => 'A cache tesztértéke nem volt visszaolvasható.'];
        } catch (Throwable $exception) {
            report($exception);

            return ['state' => 'error', 'label' => 'Nem elérhető', 'detail' => 'Ellenőrizd a Redis/cache szolgáltatást és a naplót.'];
        }
    }
}