<?php

use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Database\Migrations\Migration;

return new class () extends Migration {
    public function up(): void
    {
        Schema::create('server_subdomains', function (Blueprint $table) {
            $table->id();
            $table->unsignedInteger('server_id')->nullable()->unique();
            // Keep orphan reservations: deleting a server must not silently free live DNS.
            $table->foreign('server_id')->references('id')->on('servers')->nullOnDelete();
            $table->string('hostname', 253)->unique();
            $table->string('zone_id', 32);
            $table->uuid('ownership');
            $table->string('ip', 45);
            $table->unsignedSmallInteger('port');
            $table->string('status')->default('pending');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('server_subdomains');
    }
};
