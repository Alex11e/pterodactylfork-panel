<?php

namespace Pterodactyl\Tests\Integration\Models;

use Pterodactyl\Models\Node;
use Pterodactyl\Models\Location;
use Pterodactyl\Tests\Integration\IntegrationTestCase;

class NodeConfigurationTest extends IntegrationTestCase
{
    public function testHttpNodeConfigurationDoesNotContainCertificatePaths(): void
    {
        $node = Node::factory()->for(Location::factory())->create([
            'fqdn' => '192.168.0.205',
            'scheme' => 'http',
            'behind_proxy' => false,
        ]);

        $configuration = $node->getConfiguration();

        $this->assertFalse($configuration['api']['ssl']['enabled']);
        $this->assertArrayNotHasKey('cert', $configuration['api']['ssl']);
        $this->assertArrayNotHasKey('key', $configuration['api']['ssl']);
    }

    public function testHttpsNodeConfigurationContainsCertificatePaths(): void
    {
        $node = Node::factory()->for(Location::factory())->create([
            'fqdn' => 'node.example.com',
            'scheme' => 'https',
            'behind_proxy' => false,
        ]);

        $ssl = $node->getConfiguration()['api']['ssl'];

        $this->assertTrue($ssl['enabled']);
        $this->assertSame('/etc/letsencrypt/live/node.example.com/fullchain.pem', $ssl['cert']);
        $this->assertSame('/etc/letsencrypt/live/node.example.com/privkey.pem', $ssl['key']);
    }
}