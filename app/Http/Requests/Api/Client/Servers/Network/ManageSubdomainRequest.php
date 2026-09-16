<?php

namespace Pterodactyl\Http\Requests\Api\Client\Servers\Network;

use Pterodactyl\Models\Server;
use Pterodactyl\Http\Requests\Api\Client\ClientApiRequest;

class ManageSubdomainRequest extends ClientApiRequest
{
    public function authorize(): bool
    {
        $server = $this->route('server');

        return $server instanceof Server && ($this->user()->root_admin || $this->user()->id === $server->owner_id);
    }

    public function rules(): array
    {
        return $this->isMethod('POST') ? ['label' => 'required|string|max:63|regex:/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/D'] : [];
    }
}
