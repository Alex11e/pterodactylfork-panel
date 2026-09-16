<?php

namespace Pterodactyl\Console\Commands\Server;

use Illuminate\Console\Command;
use Pterodactyl\Models\Node;
use Pterodactyl\Services\Nodes\NginxGateway;

class RemoteAccessNginxCommand extends Command
{
    protected $signature = 'p:remote-access:nginx';

    protected $description = 'Print the private Wings gateway snippet for the panel nginx server block.';

    public function handle(): int
    {
        $nodes = [];
        foreach (Node::query()->orderBy('id')->get() as $node) {
            $nodes[$node->id] = $node->getConnectionAddress();
        }

        // Validate the full configuration before emitting anything to stdout.
        $this->output->write(NginxGateway::render($nodes));

        return self::SUCCESS;
    }
}
