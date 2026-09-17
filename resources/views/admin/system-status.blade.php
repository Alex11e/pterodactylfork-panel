@extends('layouts.admin')

@section('title')
    System Status
@endsection

@section('content-header')
    <h1>System Status<small>Panel, deployment and security checks.</small></h1>
    <ol class="breadcrumb">
        <li><a href="{{ route('admin.index') }}">Admin</a></li>
        <li class="active">System Status</li>
    </ol>
@endsection

@section('content')
<div class="row">
    <div class="col-sm-6">
        <div class="box box-primary">
            <div class="box-header with-border"><h3 class="box-title">Services</h3></div>
            <div class="box-body no-padding">
                <table class="table table-hover">
                    @foreach($checks as $name => $check)
                        <tr>
                            <td>{{ ucfirst($name) }}</td>
                            <td class="text-right">
                                <span class="label label-{{ $check['state'] === 'ok' ? 'success' : ($check['state'] === 'error' ? 'danger' : 'info') }}">{{ $check['label'] }}</span>
                            </td>
                            <td>{{ $check['detail'] }}</td>
                        </tr>
                    @endforeach
                </table>
            </div>
        </div>
    </div>
    <div class="col-sm-6">
        <div class="box box-primary">
            <div class="box-header with-border"><h3 class="box-title">Deployment</h3></div>
            <div class="box-body no-padding">
                <table class="table table-hover">
                    <tr><td>Panel version</td><td><code>{{ $deployment['version'] }}</code></td></tr>
                    <tr><td>Application URL</td><td><code>{{ $deployment['url'] }}</code></td></tr>
                    <tr><td>Backend</td><td>{{ $deployment['backend'] }}</td></tr>
                    <tr><td>Bind address</td><td><code>{{ $deployment['bind_address'] }}</code></td></tr>
                    <tr><td>Cloudflare Tunnel</td><td>{{ $deployment['tunnel_hostname'] }}</td></tr>
                    <tr><td>Registered nodes</td><td>{{ $deployment['nodes'] }}</td></tr>
                </table>
            </div>
        </div>
    </div>
</div>
<div class="row">
    <div class="col-xs-12">
        <div class="box box-default">
            <div class="box-header with-border"><h3 class="box-title">Security</h3></div>
            <div class="box-body no-padding">
                <table class="table table-hover">
                    <tr><td>Debug mode</td><td><span class="label label-{{ $security['debug'] ? 'danger' : 'success' }}">{{ $security['debug'] ? 'Enabled' : 'Disabled' }}</span></td></tr>
                    <tr><td>HTTPS application URL</td><td><span class="label label-{{ $security['https'] ? 'success' : 'warning' }}">{{ $security['https'] ? 'Enabled' : 'HTTP' }}</span></td></tr>
                    <tr><td>Localhost origin</td><td><span class="label label-{{ $security['localhost_origin'] ? 'success' : 'info' }}">{{ $security['localhost_origin'] ? 'Yes' : 'Public hostname' }}</span></td></tr>
                    <tr><td>Trusted proxies</td><td><code>{{ is_array($security['trusted_proxies']) ? implode(',', $security['trusted_proxies']) : $security['trusted_proxies'] }}</code></td></tr>
                </table>
            </div>
        </div>
    </div>
</div>
@endsection