<?php

// Dependency-free contract test: execute the production provider against a fake HTTP transport.

namespace Symfony\Component\HttpKernel\Exception {
    class HttpException extends \RuntimeException
    {
        public function __construct(public int $status, string $message)
        {
            parent::__construct($message);
        }
    }
}

namespace Illuminate\Http\Client { class ConnectionException extends \RuntimeException
{
} }

namespace Illuminate\Support\Facades {
    class Http
    {
        public static array $queue = [];
        public static array $sent = [];

        public static function withToken($token): self
        {
            return new self();
        }

        public function acceptJson(): self
        {
            return $this;
        }

        public function connectTimeout($seconds): self
        {
            return $this;
        }

        public function timeout($seconds): self
        {
            return $this;
        }

        public function send($method, $url, $options): object
        {
            self::$sent[] = [$method, $url, $options];
            $response = array_shift(self::$queue);
            if ($response instanceof \Throwable) {
                throw $response;
            }
            if ($response === null) {
                throw new \RuntimeException('Unexpected HTTP call');
            }

            return new class ($response) {
                public function __construct(private array $data)
                {
                }

                public function successful(): bool
                {
                    return $this->data['success'];
                }

                public function json(?string $key = null): mixed
                {
                    return $key ? ($this->data[$key] ?? null) : $this->data;
                }
            };
        }
    }
}

namespace {
    use Illuminate\Support\Facades\Http;
    use Pterodactyl\Services\Subdomains\CloudflareDns;
    use Symfony\Component\HttpKernel\Exception\HttpException;

    function config($key)
    {
        return 'test-token';
    }
    function abort_if($condition, $status, $message = '')
    {
        if ($condition) {
            throw new HttpException($status, $message);
        }
    }
    function abort_unless($condition, $status, $message = '')
    {
        abort_if(!$condition, $status, $message);
    }
    $checks = 0;
    function check($condition)
    {
        global $checks;
        ++$checks;
        if (!$condition) {
            throw new RuntimeException('Check ' . $checks . ' failed');
        }
    }
    function rejected($callback, $status)
    {
        try {
            $callback();
        } catch (HttpException $e) {
            check($e->status === $status);

            return;
        }
        check(false);
    }
    require __DIR__ . '/../app/Services/Subdomains/CloudflareDns.php';
    $dns = new CloudflareDns();
    $zone = str_repeat('a', 32);
    $owned = ['id' => 'record', 'type' => 'A', 'comment' => 'alex-panel:owner'];
    $foreign = ['id' => 'foreign', 'type' => 'A', 'comment' => 'unrelated'];
    check($dns->ownedRecord([], 'owner') === null);
    check($dns->ownedRecord([$owned], 'owner') === $owned);
    rejected(fn () => $dns->ownedRecord([$foreign], 'owner'), 409);
    rejected(fn () => $dns->ownedRecord([$owned, $foreign], 'owner'), 409);
    rejected(fn () => $dns->ownedRecord([array_merge($owned, ['type' => 'CNAME'])], 'owner'), 409);
    rejected(fn () => $dns->find('../other', 'game.example.com'), 503);
    check(Http::$sent === []);
    Http::$queue = [['success' => true, 'result' => [$foreign, $owned]], ['success' => true]];
    $dns->removeOwned($zone, 'game.example.com', 'owner');
    check(count(Http::$sent) === 2);
    check(Http::$sent[0][2]['query']['name'] === 'game.example.com');
    check(Http::$sent[1][0] === 'DELETE');
    check(str_ends_with(Http::$sent[1][1], '/dns_records/record'));
    Http::$sent = [];
    Http::$queue = [['success' => true, 'result' => [$foreign]]];
    $dns->removeOwned($zone, 'game.example.com', 'owner');
    check(count(Http::$sent) === 1);
    Http::$queue = [['success' => true, 'result' => [$owned, $owned]]];
    rejected(fn () => $dns->removeOwned($zone, 'game.example.com', 'owner'), 409);
    Http::$queue = [['success' => true, 'result' => [], 'result_info' => ['total_count' => 101]]];
    rejected(fn () => $dns->find($zone, 'game.example.com'), 409);
    Http::$queue = [['success' => false]];
    rejected(fn () => $dns->find($zone, 'game.example.com'), 503);
    Http::$sent = [];
    Http::$queue = [new Illuminate\Http\Client\ConnectionException('secret-provider-details')];
    rejected(fn () => $dns->request('POST', $zone, '', []), 503);
    check(count(Http::$sent) === 1); // A POST timeout must never be automatically retried.
    echo "Subdomain provider: $checks checks passed.\n";
}
