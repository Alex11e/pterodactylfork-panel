<?php

namespace Pterodactyl\Tests\Integration\Api\Client\Server;

use Illuminate\Support\Facades\DB;
use Pterodactyl\Models\Permission;
use Illuminate\Support\Facades\Http;
use Pterodactyl\Tests\Integration\Api\Client\ClientApiIntegrationTestCase;

class SubdomainControllerTest extends ClientApiIntegrationTestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config()->set('subdomains', ['enabled' => true, 'domain' => 'games.example.com', 'zone_id' => str_repeat('a', 32), 'token' => 'test-token']);
        Http::preventStrayRequests();
    }

    protected function tearDown(): void
    {
        DB::table('server_subdomains')->delete();
        parent::tearDown();
    }

    public function testSubuserCannotCreateEvenWithAllocationPermissions(): void
    {
        [$user, $server] = $this->generateTestAccount([Permission::ACTION_ALLOCATION_READ, Permission::ACTION_ALLOCATION_CREATE]);
        $this->actingAs($user)->postJson($this->link($server, '/network/subdomain'), ['label' => 'survival'])->assertForbidden();
        $this->actingAs($user)->getJson($this->link($server, '/network/subdomain'))->assertOk()->assertJsonPath('can_manage', false);
        Http::assertNothingSent();
    }

    public function testCreateAndRecoverPendingRecordWithoutDuplicatePost(): void
    {
        [$user, $server] = $this->generateTestAccount();
        $server->allocation->forceFill(['ip' => '8.8.8.8'])->save();
        Http::fake(['api.cloudflare.com/*' => Http::sequence()
            ->push(['success' => true, 'result' => []])
            ->push(['success' => false], 503)]);
        $url = $this->link($server, '/network/subdomain');
        $this->actingAs($user)->postJson($url, ['label' => 'survival'])->assertStatus(503);
        $row = DB::table('server_subdomains')->where('server_id', $server->id)->first();
        $this->assertSame('pending', $row->status);
        // Simulate a provider that committed the original POST before losing its response.
        Http::fake(['api.cloudflare.com/*' => Http::sequence()
            ->push(['success' => true, 'result' => [['id' => 'record-id', 'type' => 'A', 'comment' => 'alex-panel:' . $row->ownership]]])
            ->push(['success' => true, 'result' => []])]);
        $this->actingAs($user)->putJson($url)->assertOk();
        Http::assertSent(fn ($request) => $request->method() === 'PUT' && $request['proxied'] === false && $request['content'] === '8.8.8.8');
        $this->assertSame('active', DB::table('server_subdomains')->where('id', $row->id)->value('status'));
    }

    public function testForeignDnsRecordIsNeverOverwrittenOrDeleted(): void
    {
        [$user, $server] = $this->generateTestAccount();
        $server->allocation->forceFill(['ip' => '8.8.8.8'])->save();
        Http::fake(['api.cloudflare.com/*' => Http::response(['success' => true, 'result' => [['id' => 'foreign', 'type' => 'A', 'comment' => 'someone-else']]])]);
        $url = $this->link($server, '/network/subdomain');
        $this->actingAs($user)->postJson($url, ['label' => 'survival'])->assertStatus(409);
        $this->actingAs($user)->deleteJson($url)->assertOk();
        Http::assertNotSent(fn ($request) => $request->method() !== 'GET');
        $this->assertSame(0, DB::table('server_subdomains')->count());
    }

    public function testInvalidLabelsAndPrivateTargetsDoNotContactCloudflare(): void
    {
        [$user, $server] = $this->generateTestAccount();
        $url = $this->link($server, '/network/subdomain');
        $this->actingAs($user)->postJson($url, ['label' => '../panel'])->assertStatus(422);
        $server->allocation->forceFill(['ip' => '127.0.0.1'])->save();
        $this->actingAs($user)->postJson($url, ['label' => 'survival'])->assertStatus(422);
        Http::assertNothingSent();
    }
}
