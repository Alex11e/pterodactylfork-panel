<?php

namespace Pterodactyl\Console\Commands\Node;

use Pterodactyl\Models\Node;
use Illuminate\Console\Command;
use Pterodactyl\Models\Location;
use Symfony\Component\Yaml\Yaml;
use Illuminate\Support\Facades\DB;
use Pterodactyl\Models\Allocation;
use Pterodactyl\Services\Nodes\NodeCreationService;
use Pterodactyl\Repositories\Wings\DaemonConfigurationRepository;

class InstallerNodeCommand extends Command
{
    protected $signature = 'p:installer:node {--host=} {--ip=} {--port=25565} {--memory=2048} {--disk=10240} {--gateway=} {--subnet=} {--check}';
    protected $description = 'Provision the local all-in-one node, or check its authenticated Wings connection.';

    public function handle(NodeCreationService $creator, DaemonConfigurationRepository $daemon): int
    {
        $description = 'Managed by Alex Panel all-in-one installer.';
        $node = Node::query()->where('description', $description)->first();
        if ($this->option('check')) {
            if (!$node) {
                $this->error('Local node has not been provisioned.');

                return 1;
            }
            try {
                $daemon->setNode($node)->getSystemInformation();
            } catch (\Throwable) {
                $this->error('Wings authenticated connection is not ready. Check Wings logs.');

                return 1;
            }
            $this->info('Wings authenticated connection: OK');

            return 0;
        }
        foreach (['host', 'ip', 'gateway'] as $option) {
            if (!filter_var($this->option($option), FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
                $this->error('Valid IPv4 required: ' . $option);

                return 1;
            }
        }
        $subnet = explode('/', (string) $this->option('subnet'));
        if (count($subnet) !== 2 || !filter_var($subnet[0], FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) || !ctype_digit($subnet[1]) || (int) $subnet[1] > 32) {
            $this->error('Valid Docker IPv4 subnet required.');

            return 1;
        }
        foreach (['port' => 65535, 'memory' => 2147483647, 'disk' => 2147483647] as $option => $max) {
            if (filter_var($this->option($option), FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => $max]]) === false) {
                $this->error('Invalid positive value: ' . $option);

                return 1;
            }
        }
        // Run only from the root-owned installer, never exposed as an HTTP endpoint.
        $node = DB::transaction(function () use ($node, $description, $creator) {
            if (!$node) {
                $location = Location::query()->firstOrCreate(['short' => 'alex-local'], ['long' => 'Local all-in-one installation']);
                $node = $creator->handle([
                    'name' => 'Alex Local', 'description' => $description, 'location_id' => $location->id,
                    'fqdn' => $this->option('host'), 'scheme' => 'http', 'behind_proxy' => false,
                    'memory' => (int) $this->option('memory'), 'disk' => (int) $this->option('disk'),
                    'memory_overallocate' => 0, 'disk_overallocate' => 0, 'upload_size' => 100,
                    'daemonListen' => 8081, 'daemonSFTP' => 2022, 'daemonBase' => '/var/lib/pterodactyl/volumes',
                ]);
            } else {
                // Preserve tokens, limits, allocations and existing game servers on reruns.
                $node->forceFill(['fqdn' => $this->option('host'), 'scheme' => 'http', 'daemonListen' => 8081])->save();
            }
            Allocation::query()->firstOrCreate([
                'node_id' => $node->id, 'ip' => $this->option('ip'), 'port' => (int) $this->option('port'),
            ]);

            return $node;
        });
        $config = $node->getConfiguration();
        $config['api']['host'] = '0.0.0.0';
        $config['api']['ssl'] = ['enabled' => false];
        $config['docker']['network'] = [
            'name' => 'alex-games', 'network_mode' => 'alex-games', 'interface' => $this->option('gateway'),
            'interfaces' => ['v4' => ['subnet' => $this->option('subnet'), 'gateway' => $this->option('gateway')]],
        ];
        // The installer redirects this secret-bearing output directly into a mode-600 file.
        $this->output->write(Yaml::dump($config, 6, 2, Yaml::DUMP_EMPTY_ARRAY_AS_SEQUENCE));

        return 0;
    }
}
