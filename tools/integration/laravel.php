<?php

/*
 * Helper for the local DRS Starter ↔ Laravel integration test (development database only).
 * Usage: php laravel.php <path-to-drs_v2> seed|approve <code> <email>|state
 * Never run against a production database: it refuses unless DB_CONNECTION=sqlite.
 */

$root = $argv[1] ?? null;
if (! $root || ! is_file($root.'/artisan')) {
    fwrite(STDERR, "usage: php laravel.php <drs_v2 path> <command>\n");
    exit(2);
}
require $root.'/vendor/autoload.php';
$app = require $root.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

if (config('database.default') !== 'sqlite') {
    fwrite(STDERR, "refusing: integration helper runs only on a sqlite development database\n");
    exit(3);
}

use App\Domain\RaceControl\StartQueueService;
use App\Domain\Starter\StarterPairingService;
use App\Models\Championship;
use App\Models\CompetitionClass;
use App\Models\Discipline;
use App\Models\Event;
use App\Models\EventEntry;
use App\Models\Game;
use App\Models\GameProfile;
use App\Models\Player;
use App\Models\RaceControlSetting;
use App\Models\Season;
use App\Models\StartOrderItem;
use App\Models\StartOrderSnapshot;
use App\Models\StarterSlot;
use App\Models\User;

$cmd = $argv[2] ?? '';

if ($cmd === 'seed') {
    (new Database\Seeders\ReferenceDataSeeder)->run();
    $ac = Game::where('code', Game::ASSETTO_CORSA)->value('id');
    $ch = Championship::create(['name' => 'DRS HC (integration)', 'slug' => 'int-hc', 'discipline_id' => Discipline::where('code', 'hillclimb')->value('id'), 'default_game_id' => $ac]);
    $season = Season::create(['championship_id' => $ch->id, 'game_id' => $ac, 'name' => 'Int', 'slug' => 'int', 'number' => 99, 'status' => 'active']);
    $class = CompetitionClass::create(['season_id' => $season->id, 'name' => 'Integrare', 'code' => 'int']);
    $event = Event::create(['season_id' => $season->id, 'sequence_number' => 1, 'name' => 'Etapa integrare', 'slug' => 'int-e1', 'status' => 'live', 'scheduled_at' => now()]);
    $operator = User::factory()->create(['email' => 'operator@int.test']);
    $operator->assignRole('race_operator');
    $sc = User::factory()->create(['email' => 'sc@int.test']);
    $sc->assignRole('safety_car');
    $snapshot = StartOrderSnapshot::create(['event_id' => $event->id, 'competition_class_id' => $class->id, 'version' => 1, 'status' => 'published', 'method' => 'integration', 'params' => [], 'published_at' => now()]);
    foreach (['a', 'b'] as $i => $k) {
        $u = User::factory()->create(['email' => "pilot-$k@int.test"]);
        $p = Player::create(['display_name' => 'Pilot '.strtoupper($k), 'slug' => "int-$k", 'user_id' => $u->id]);
        $gp = GameProfile::create(['player_id' => $p->id, 'game_id' => $ac, 'external_id_type' => 'steamid64', 'external_id' => '7656119000000990'.$i, 'verification_status' => 'steam_verified']);
        $e = EventEntry::create(['event_id' => $event->id, 'player_id' => $p->id, 'competition_class_id' => $class->id, 'game_profile_id' => $gp->id, 'entry_status' => 'accepted', 'attendance_status' => 'present', 'race_number' => 21 + $i]);
        StartOrderItem::create(['start_order_snapshot_id' => $snapshot->id, 'event_entry_id' => $e->id, 'position' => $i + 1]);
    }
    app(StartQueueService::class)->build($event, $class, 1, $operator);
    // Short timings for the HTTP lifecycle test only (the 50 s / ±10 s rules are covered by the PHPUnit tests).
    RaceControlSetting::for($event, $class)->forceFill(['phase' => 'run1', 'current_run' => 1, 'starter_lead_seconds' => 12,
        'starter_interval_seconds' => 16, 'starter_window_before_seconds' => 4, 'starter_window_after_seconds' => 4])->save();
    echo json_encode(['event_id' => $event->id, 'class_id' => $class->id]), "\n";
    exit(0);
}

if ($cmd === 'approve') {
    $user = User::where('email', $argv[4] ?? '')->firstOrFail();
    app(StarterPairingService::class)->approve($user, $argv[3] ?? '');
    echo "approved\n";
    exit(0);
}

if ($cmd === 'state') {
    echo json_encode(StarterSlot::orderBy('id')->get(['id', 'event_entry_id', 'attempt', 'status', 'resolution', 'dns_pending'])->toArray(), JSON_PRETTY_PRINT), "\n";
    exit(0);
}

fwrite(STDERR, "unknown command\n");
exit(2);
