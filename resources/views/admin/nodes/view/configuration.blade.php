@extends('layouts.admin')

@section('title')
    {{ $node->name }}: Configuration
@endsection

@section('content-header')
    <h1>{{ $node->name }}<small>Your daemon configuration file.</small></h1>
    <ol class="breadcrumb">
        <li><a href="{{ route('admin.index') }}">Admin</a></li>
        <li><a href="{{ route('admin.nodes') }}">Nodes</a></li>
        <li><a href="{{ route('admin.nodes.view', $node->id) }}">{{ $node->name }}</a></li>
        <li class="active">Configuration</li>
    </ol>
@endsection

@section('content')
<div class="row">
    <div class="col-xs-12">
        <div class="nav-tabs-custom nav-tabs-floating">
            <ul class="nav nav-tabs">
                <li><a href="{{ route('admin.nodes.view', $node->id) }}">About</a></li>
                <li><a href="{{ route('admin.nodes.view.settings', $node->id) }}">Settings</a></li>
                <li class="active"><a href="{{ route('admin.nodes.view.configuration', $node->id) }}">Configuration</a></li>
                <li><a href="{{ route('admin.nodes.view.allocation', $node->id) }}">Allocation</a></li>
                <li><a href="{{ route('admin.nodes.view.servers', $node->id) }}">Servers</a></li>
            </ul>
        </div>
    </div>
</div>
<div class="row">
    <div class="col-sm-8">
        <div class="box box-primary">
            <div class="box-header with-border">
                <h3 class="box-title">Configuration File</h3>
            </div>
            <div class="box-body">
                <pre class="no-margin">{{ $node->getYamlConfiguration() }}</pre>
            </div>
            <div class="box-footer">
                <p class="no-margin">A telepítő által kezelt telepítésnél a fájl helye: <code>{{ config('pterodactyl.wings.config_path') }}</code>.</p>
            </div>
        </div>
    </div>
    <div class="col-sm-4">
        <div class="box box-success">
            <div class="box-header with-border">
                <h3 class="box-title">Auto-Deploy</h3>
            </div>
            <div class="box-body">
                <p class="text-muted small">
                    Use the button below to generate a custom deployment command that can be used to configure
                    wings on the target server with a single command.
                </p>
            </div>
            <div class="box-footer">
                <button type="button" id="configTokenBtn" class="btn btn-sm btn-default" style="width:100%;">Generate Token</button>
                <p class="text-muted small no-margin" style="margin-top:10px;">A token csak a konfiguráló parancshoz használható, és nem jelenik meg a node YAML-ban.</p>
            </div>
        </div>
    </div>
</div>
@endsection

@section('footer-scripts')
    @parent
    <script>
    function escapeHtml(value) {
        return $('<div>').text(value).html();
    }

    $('#configTokenBtn').on('click', function (event) {
        $.ajax({
            method: 'POST',
            url: '{{ route('admin.nodes.view.configuration.token', ['node' => $node->id]) }}',
            headers: { 'X-CSRF-TOKEN': '{{ csrf_token() }}' },
        }).done(function (data) {
            const panelUrl = @json(rtrim(config('app.url'), '/'));
            const token = data.token;
            const node = data.node;
            const allowInsecure = @json((bool) config('app.debug')) ? ' --allow-insecure' : '';
            const configDirectory = @json(dirname(config('pterodactyl.wings.config_path')));
            const command = 'cd ' + configDirectory + ' && sudo wings configure --panel-url ' + panelUrl + ' --token ' + token + ' --node ' + node + allowInsecure;
            swal({
                type: 'success',
                title: 'Token created.',
                text: '<p>To auto-configure your node run the following command:<br /><small><pre>' + escapeHtml(command) + '</pre></small></p>',
                html: true
            })
        }).fail(function () {
            swal({
                title: 'Error',
                text: 'Something went wrong creating your token.',
                type: 'error'
            });
        });
    });
    </script>
@endsection
