# Bit-perfect mode, the player's HQPlayer page and the connection status
# (1.1.0).
#
# What is proved here, and why each matters:
#   * ReplayGain is SHOWN (canDoReplayGain) because the bridge USES it, and in
#     bit-perfect mode unity is ASSERTED - the one place 0.00 is sent on
#     purpose, since album_gain overrides HQPlayer's own tag read.
#   * The volume-control pref is written ONLY on a real flip of the switch,
#     and put back as it was - the ledger rule "the plugin never writes
#     digitalVolumeControl" still holds for anything automatic.
#   * Native-only refuses a converted tier the way a refused PlaylistAdd
#     fails, and never lets one into HQPlayer's playlist through a hand-over.
#   * Both settings pages draw finished strings from one formatter.
use strict; use warnings;
BEGIN { package main; use constant DEBUGLOG=>0; use constant INFOLOG=>0; use constant WEBUI=>1; }
use lib '.';

our ($BASE_SAVED);
require Slim::Web::Settings;
require Slim::Utils::Strings;
{
    no warnings qw(redefine once);
    # Saves the way LMS's base handler does: every name prefs() returns, from
    # pref_<name>, only when saveSettings is set; then beforeRender.
    *Slim::Web::Settings::handler = sub {
        my ( $class, $client, $params ) = @_;
        $BASE_SAVED = 0;
        if ( $params->{saveSettings} ) {
            my ( $prefs, @names ) = $class->prefs($client);
            $prefs->set( $_, $params->{"pref_$_"} ) for @names;
            $BASE_SAVED = 1;
        }
        $class->beforeRender( $params, $client );
        return 'rendered';
    };
    my %en;
    open my $fh, '<', '../HQPlayerBridge/strings.txt' or die $!;
    my $key;
    while (<$fh>) {
        if (/^(\S+)\s*$/) { $key = $1 }
        elsif ( defined $key && /^\tEN\t(.*)$/ ) { $en{$key} = $1 }
    }
    *Slim::Utils::Strings::string  = sub { $en{ $_[0] } // $_[0] };
    *Slim::Utils::Strings::cstring = sub { $en{ $_[1] } // $_[1] };
}

require Plugins::HQPlayerBridge::Player;
require Plugins::HQPlayerBridge::Plugin;
require Plugins::HQPlayerBridge::Settings;
require Plugins::HQPlayerBridge::PlayerSettings;
require Slim::Utils::Timers;

my ($pass,$fail)=(0,0);
sub is { my($got,$want,$name)=@_; $got//='(undef)'; $want//='(undef)';
  if ($got eq $want){$pass++; printf "  ok   %s\n",$name}
  else {$fail++; printf "  FAIL %s\n        got: %s\n       want: %s\n",$name,$got,$want} }
# see the note on ok() in t_player.pl - a failed match returns the EMPTY LIST
sub ok { my $n = pop; my $c = @_ ? $_[0] : 0;
  $c ? ($pass++, printf "  ok   %s\n",$n) : ($fail++, printf "  FAIL %s\n",$n) }

{
    package FakeCtl;    sub up { 1 } sub connected { 1 } sub proven { 1 }
    package FakeTrack;
    sub new { bless {%{$_[1]}}, $_[0] }
    sub title { $_[0]{title} } sub artistName {} sub albumname {} sub coverid {}
    sub id { $_[0]{id} } sub secs { 100 } sub content_type { $_[0]{ct} }
    sub url { $_[0]{url} } sub replay_peak {} sub remote { 0 }
    package FakeSong;
    sub new { bless { t => $_[1] }, $_[0] }
    sub currentTrack { $_[0]{t} }
    sub replayGain { $_[0]{rg} }
    sub _rg { $_[0]{rg} = $_[1]; $_[0] }
    sub directstream {} sub streamUrl {} sub currentTrackHandler {}
    package FakeController;
    sub new { bless { failed => [] }, shift }
    sub song { $_[0]{song} }
    sub playerStreamingFailed { push @{ $_[0]{failed} }, $_[2] }
    sub playerStatusHeartbeat {} sub playerTrackStarted {} sub playerEndOfStream {}
    sub playerReadyToStream {} sub playerStopped {}
}

my @sent;
{
    no warnings 'redefine';
    *Plugins::HQPlayerBridge::Player::_send = sub { push @sent, $_[1]; return };
    *Plugins::HQPlayerBridge::Player::_startPolling = sub {};
    *Plugins::HQPlayerBridge::Player::_stopPolling  = sub {};
}

my $pp = Slim::Utils::Prefs::preferences('plugin.hqplayerbridge');
my $sp = Slim::Utils::Prefs::preferences('server');

my $c = Plugins::HQPlayerBridge::Player->new('02:bb:00:00:00:01', 'paddr', 1.0, undef, 12, undef);
$c->hqControl( bless {}, 'FakeCtl' );
$c->name('Salon');

my $local = FakeTrack->new({ title=>'t', id=>101, ct=>'flc', url=>'file:///m/a.flac' });
my $alac  = FakeTrack->new({ title=>'t', id=>102, ct=>'alc', url=>'file:///m/b.m4a' });

print "-- ReplayGain: shown, and neutralised in bit-perfect mode --\n";
is( $c->canDoReplayGain(0), '1', 'canDoReplayGain is 1, so LMS shows the ReplayGain setting it already uses' );

$pp->client($c)->set( 'bitperfect', 0 );
ok( scalar( $c->_metadata( FakeSong->new($local)->_rg(-4.07) ) =~ /\balbum_gain="-4\.07"/ ),
    'OFF: LMS\'s figure is still sent unchanged' );
ok( scalar( $c->_metadata( FakeSong->new($local) ) !~ /album_gain/ ),
    'OFF: no figure still means no attribute - the old rule is untouched' );

$pp->client($c)->set( 'bitperfect', 1 );
ok( scalar( $c->_metadata( FakeSong->new($local)->_rg(-4.07) ) =~ /\balbum_gain="0\.00"/ ),
    'ON: unity replaces LMS\'s figure' );
ok( scalar( $c->_metadata( FakeSong->new($local) ) =~ /\balbum_gain="0\.00"/ ),
    'ON: unity is ASSERTED even with no figure - it overrides HQPlayer\'s own tag read' );
is( $c->hqGainSent, '0', 'and the status knows unity was sent' );
Slim::Player::ReplayGain->_setTestGain(6.68);
ok( scalar( $c->_metadata( FakeSong->new($local) ) =~ /\balbum_gain="0\.00"/ ),
    'ON: a handler/fetchGainMode figure is overridden too' );
Slim::Player::ReplayGain->_setTestGain(undef);

print "-- the bitrate limit --\n";
$sp->client($c)->set( 'maxBitrate', 320 );
is( $c->_enforceBitrate, '1', 'a 320 kbps cap is reported as changed' );
is( $sp->client($c)->get('maxBitrate'), '0', 'and set back to 0 (no limit)' );
is( $c->_enforceBitrate, '0', 'a 0 already in place is left alone' );

print "-- switching the mode: volume control and HQPlayer's level --\n";
$sp->client($c)->set( 'digitalVolumeControl', 1 );
$c->hqVolMax(0); $c->hqVolMin(-60);
@sent = ();
$c->applyBitPerfect(1);
is( $sp->client($c)->get('digitalVolumeControl'), '0', 'ON: LMS volume control set to fixed' );
is( $pp->client($c)->get('bpSavedVolCtl'), '1', 'ON: the user\'s own choice is kept' );
is( join( ',', @sent ), '<Volume value="0"/>', 'ON: HQPlayer set to unity once' );

$c->applyBitPerfect(1);
is( $pp->client($c)->get('bpSavedVolCtl'), '1', 'a second ON does not record our forced 0 as the user\'s choice' );

$c->hqVolMax(-6);
@sent = ();
$c->_sendUnity;
is( join( ',', @sent ), '<Volume value="-6"/>', 'a ceiling below 0 dB is respected, as volume() respects it' );
$c->hqVolMax(0);

$c->applyBitPerfect(0);
is( $sp->client($c)->get('digitalVolumeControl'), '1', 'OFF: volume control put back as it was' );
is( $pp->client($c)->get('bpSavedVolCtl'), '(undef)', 'OFF: the saved value is cleared' );

print "-- the change handler acts only on a real flip --\n";
{
    my @calls;
    no warnings qw(redefine once);
    local *Plugins::HQPlayerBridge::Player::applyBitPerfect = sub { push @calls, $_[1] };
    Plugins::HQPlayerBridge::Plugin::_bitPerfectChanged( 'bitperfect', 0, $c, undef );
    is( scalar @calls, '0', 'undef -> 0 (a first save with it off) does nothing - a fixed volume the user chose survives' );
    Plugins::HQPlayerBridge::Plugin::_bitPerfectChanged( 'bitperfect', 1, $c, 0 );
    is( join( ',', @calls ), '1', '0 -> 1 switches it on' );
    Plugins::HQPlayerBridge::Plugin::_bitPerfectChanged( 'bitperfect', 0, $c, 1 );
    is( join( ',', @calls ), '1,0', '1 -> 0 switches it off' );
}

print "-- native only --\n";
$pp->client($c)->set( 'bitperfect', 0 );
$pp->client($c)->set( 'nativeonly', 1 );
is( $c->nativeOnly, '0', 'native only means nothing while bit-perfect is off' );
$pp->client($c)->set( 'bitperfect', 1 );
is( $c->nativeOnly, '1', 'and applies once it is on' );
is( join( ',', map { $c->_refuses($_) } 1, 3, 4, 5 ), '0,1,1,0',
    'tiers 3 and 4 (LMS converts or relays) are refused; 1 and 5 (untouched) are not' );

my $lc = FakeController->new;
$c->controller($lc);
$lc->{song} = FakeSong->new($alac);
@sent = ();
Slim::Utils::Timers::_reset();
is( $c->play({ controller => $lc }), '1', 'a refused track still answers play() as started - the failure is deferred' );
is( join( ',', @sent ), '<Stop/>,<PlaylistClear/>', 'what was playing is stopped, and nothing is added' );
is( scalar @{ $lc->{failed} }, '0', 'nothing failed yet - the refusal waits one turn of the loop' );
Slim::Utils::Timers::_fireAll();
is( join( ',', @{ $lc->{failed} } ), 'PLUGIN_HQPLAYER_BP_REFUSED', 'then LMS is told, with the reason, and skips it' );

# A refusal for a load since superseded must not fail the new one.
@{ $lc->{failed} } = ();
$c->play({ controller => $lc });
$c->_newGeneration;
Slim::Utils::Timers::_fireAll();
is( scalar @{ $lc->{failed} }, '0', 'a refusal belonging to a superseded load is dropped' );

# Hand-over: a converted next track is held for a normal load, never appended.
$c->hqTier(1);
@sent = ();
$c->_handOver( FakeSong->new($alac), undef );
is( scalar( grep { /PlaylistAdd/ } @sent ), '0', 'a refused next track is never appended to HQPlayer\'s playlist' );
is( ( $c->hqNext || {} )->{mode}, 'load', 'it is held for a normal load, where it is refused' );
is( $c->hqTier, '1', 'and the playing track\'s tier is untouched' );

$pp->client($c)->set( 'nativeonly', 0 );
$c->hqNext(undef);

print "-- the player page --\n";
my $PS = 'Plugins::HQPlayerBridge::PlayerSettings';
is( $PS->validFor($c), '1', 'listed for an HQPlayer player' );
is( $PS->validFor( bless [], 'Slim::Player::Client' ), '0', 'and not for any other player' );
is( $PS->needsClient, '1', 'it is a player page' );

$pp->client($c)->set( 'bitperfect', 1 );
my %p = ( saveSettings => 1 );
$PS->handler( $c, \%p );
is( $pp->client($c)->get('bitperfect'), '1', 'a partial POST (no sentinel) changes nothing' );

%p = ( saveSettings => 1, hqp_player_form => 1, pref_bitperfect => '0', pref_nativeonly => 'junk' );
$PS->handler( $c, \%p );
is( $pp->client($c)->get('bitperfect'), '0', 'the radio saves OFF' );
is( $pp->client($c)->get('nativeonly'), '0', 'anything but "1" is OFF' );
is( $p{hqp_bp}, '0', 'and the page redraws what was saved' );

%p = ( saveSettings => 1, hqp_player_form => 1, pref_bitperfect => '1', pref_nativeonly => '1' );
$sp->client($c)->set( 'replayGainMode', 3 );
$sp->client($c)->set( 'maxBitrate', 0 );
$sp->client($c)->set( 'digitalVolumeControl', 0 );
$c->hqTier(1); $c->hqRefusedTier(undef);
$PS->handler( $c, \%p );
is( "$p{hqp_bp}$p{hqp_native}", '11', 'the radios show ON / ON' );
is( join( '', map { $_->{ok} } @{ $p{hqp_checks} } ), '1111', 'every check is clean in bit-perfect with no cap and fixed volume' );
ok( scalar( $p{hqp_checks}[0]{text} =~ /unity/ ), 'the ReplayGain check says unity is sent' );

%p = ();
$pp->client($c)->set( 'bitperfect', 0 );
$sp->client($c)->set( 'maxBitrate', 320 );
$sp->client($c)->set( 'digitalVolumeControl', 1 );
$c->hqTier(3);
$PS->handler( $c, \%p );
is( join( '', map { $_->{ok} } @{ $p{hqp_checks} } ), '0000', 'ReplayGain on, a cap, a variable volume and a transcoded track are all flagged' );
ok( scalar( $p{hqp_checks}[1]{text} =~ /320 kbps/ ), 'the cap is named' );

print "-- the 4th check: the route of the last track --\n";
my $route = sub { $c->hqTier( $_[0] ); $c->hqRefusedTier( $_[1] ); my %q; $PS->handler( $c, \%q ); $q{hqp_checks}[3] };
is( $route->(0)->{ok}, '2', 'nothing played yet is NEUTRAL, neither clean nor flagged' );
ok( scalar( $route->(0)->{text} =~ /nothing played/ ), 'and says so' );
is( $route->(1)->{ok}, '1', 'an original file is clean' );
is( $route->(5)->{ok}, '1', 'a direct stream is clean' );
ok( scalar( $route->(5)->{text} =~ /streaming service/ ), 'and named as such' );
is( $route->(3)->{ok}, '0', 'a transcoded file is flagged' );
ok( scalar( $route->(3)->{text} =~ /transcoded to FLAC/ ), 'as transcoded' );
is( $route->(4)->{ok}, '0', 'a relayed stream is flagged' );
ok( scalar( $route->(4)->{text} =~ /relayed/ ), 'as relayed' );
is( $route->(3, 3)->{ok}, '1', 'a REFUSED track is clean - nothing converted reached HQPlayer' );
ok( scalar( $route->(3, 3)->{text} =~ /skipped/ ), 'and says it was skipped' );

# The refusal records its tier, and a real load clears it.
$pp->client($c)->set( 'bitperfect', 1 ); $pp->client($c)->set( 'nativeonly', 1 );
$c->hqRefusedTier(undef);
{
    my $lc2 = FakeController->new;
    $c->controller($lc2);
    $lc2->{song} = FakeSong->new($alac);
    $c->play({ controller => $lc2 });
    is( $c->hqRefusedTier, '3', 'a refusal records the refused tier' );
    $lc2->{song} = FakeSong->new($local);
    $c->play({ controller => $lc2 });
    is( $c->hqRefusedTier, '(undef)', 'and the next real load clears it' );
    is( $c->hqTier, '1', 'leaving the route of the track that plays' );
    Slim::Utils::Timers::_reset();
}
$pp->client($c)->set( 'bitperfect', 0 ); $pp->client($c)->set( 'nativeonly', 0 );

print "-- the connection status --\n";
my $lines = Plugins::HQPlayerBridge::Settings::statusLines( {
    connected => 'Connected - 192.168.1.20:4321', up => 1,
    mode => 'SDM', filter => 'poly-sinc-gauss-xla', tier => 'Through LMS', converted => 1,
    gain => '+0.00 dB',
} );
is( join( '|', map { $_->{label} } @$lines ),
    'Control link|Output mode|Filter|Route of the playing track|Gain on the last track sent',
    'one labelled row per fact present, none for a fact absent' );
is( join( '', map { $_->{warn} } @$lines ), '00010', 'only the converted route is flagged' );
is( Plugins::HQPlayerBridge::Settings::statusLines( { connected => 'Not connected', up => 0 } )->[0]{warn},
    '1', 'a link that is down is flagged' );

Plugins::HQPlayerBridge::Settings::setStatusSource( sub {
    { rows => [ { name => 'Salon', playerid => $c->id, path => { connected => 'Connected - x', up => 1 } } ],
      waiting => '' } } );
my %sp = ();
Plugins::HQPlayerBridge::Settings->beforeRender( \%sp );
is( $sp{hqp_status}, '1', 'the plugin page draws the status block' );
is( $sp{hqp_players}[0]{name}, 'Salon', 'with each HQPlayer named' );
is( $sp{hqp_players}[0]{lines}[0]{value}, 'Connected - x', 'and its rows' );

Plugins::HQPlayerBridge::Settings::setStatusSource( sub { die "boom\n" } );
%sp = ();
Plugins::HQPlayerBridge::Settings->beforeRender( \%sp );
is( $sp{hqp_status}, '0', 'a status source that dies leaves the block out - the settings page still draws' );

Plugins::HQPlayerBridge::PlayerSettings::setStatusSource( sub {
    { rows => [ { name => 'Other', playerid => 'nope', path => { connected => 'A' } },
                { name => 'Salon', playerid => $c->id, path => { connected => 'B', up => 1 } } ] } } );
%p = ();
$PS->handler( $c, \%p );
is( $p{hqp_status}[0]{value}, 'B', 'the player page shows THIS player\'s row, not the first one' );

print "-- the signal path carries the new facts --\n";
$pp->client($c)->set( 'bitperfect', 1 );
$pp->client($c)->set( 'nativeonly', 0 );
$c->hqTier(3);
$c->hqGainSent(0);
my $sig = Plugins::HQPlayerBridge::Plugin::signalPathFor( undef, { client => $c, instance => { ip => '192.168.1.20' } } );
is( $sig->{bitperfect}, 'On', 'the mode is named' );
is( $sig->{gain}, '+0.00 dB (bit-perfect)', 'the gain sent is shown, as unity' );
is( $sig->{converted}, '1', 'a tier 3 track is marked as touched by LMS' );
$c->hqTier(5); $c->hqGainSent(undef); $pp->client($c)->set( 'bitperfect', 0 );
$sig = Plugins::HQPlayerBridge::Plugin::signalPathFor( undef, { client => $c, instance => { ip => '192.168.1.20' } } );
is( $sig->{converted}, '0', 'a direct stream is not' );
ok( scalar( $sig->{gain} =~ /none sent/ ), 'and no gain is said as such' );
is( $sig->{bitperfect}, 'Off', 'with the mode off' );

print "-- a relay without conversion is native (1.3.0) --\n";
require Slim::Player::TranscodingHelper;
{
    package Slim::Player::Song;           # declared, so isa() resolves quietly
    sub _stub {}
    package FakeRelaySong;
    our @ISA = ('Slim::Player::Song');    # getConvertCommand2 only takes a real Song
    sub new { my ($c,%a) = @_; bless { want => 'flc', %a }, $c }
    sub wantFormat { $_[0]{want} }
    sub seekdata   { $_[0]{seek} }
    sub canSeek    { $_[0]{canseek} // 1 }
    sub currentTrackHandler { 'FakeRemoteHandler' }
    sub currentTrack { FakeTrack->new({ url => 'qobuz://123.flac', id => -9, ct => 'flc' }) }
    sub directstream { 0 } sub streamUrl { '' } sub replayGain { undef } sub streamformat { 'flc' }
    package FakeRemoteHandler;
    sub isRemote { 1 }
}
my $TH = 'Slim::Player::TranscodingHelper';
is( join( ',', map { Plugins::HQPlayerBridge::Player::tierConverts(@$_) } [1], [3], [3,1], [4], [4,1], [5] ),
    '0,1,1,1,0,0', 'tier 4 is a conversion unless relayNative; tier 3 always is; 1 and 5 never' );

$Slim::Player::TranscodingHelper::ANSWER = { command => '-', streamformat => 'flc' };
@Slim::Player::TranscodingHelper::CALLS = ();
is( $c->_relayIsPassthrough( FakeRelaySong->new ), '1', 'LMS\'s passthrough rule (command "-") for FLAC: native' );
my $call = $Slim::Player::TranscodingHelper::CALLS[0] || [];
is( join( ',', $call->[1] // '', @{ $call->[2] || [] }, '|', @{ $call->[4] || [] } ), 'flc,I,R,|',
    'it asks LMS the question Song::open asks: wanted format, streaming modes I and R, no seek option' );

$Slim::Player::TranscodingHelper::ANSWER = { command => '[flac] -dcs ... | [sox] ...', streamformat => 'flc' };
is( $c->_relayIsPassthrough( FakeRelaySong->new ), '0', 'a flac -> flac TRANSCODE (File Types rule) is not native' );
$Slim::Player::TranscodingHelper::ANSWER = { command => '[flac] ... | [lame] ...', streamformat => 'mp3' };
is( $c->_relayIsPassthrough( FakeRelaySong->new ), '0', 'nor is one to MP3' );
$Slim::Player::TranscodingHelper::ANSWER = { command => '-', streamformat => 'flc' };
@Slim::Player::TranscodingHelper::CALLS = ();
is( $c->_relayIsPassthrough( FakeRelaySong->new( want => 'aac' ) ), '0', 'a passthrough of a format HQPlayer cannot decode is not native' );
is( scalar @Slim::Player::TranscodingHelper::CALLS, '0', 'and LMS is not even asked' );
$Slim::Player::TranscodingHelper::ANSWER = sub { die "boom\n" };
is( $c->_relayIsPassthrough( FakeRelaySong->new ), '0', 'a helper that dies is NOT proof of an untouched stream' );
is( $c->_relayIsPassthrough( bless {}, 'NotASong' ), '0', 'nor is something that is not a Song' );

$Slim::Player::TranscodingHelper::ANSWER = { command => '-', streamformat => 'flc' };
@Slim::Player::TranscodingHelper::CALLS = ();
$c->_relayIsPassthrough( FakeRelaySong->new( seek => { timeOffset => 42 }, canseek => 2 ) );
$call = $Slim::Player::TranscodingHelper::CALLS[0] || [];
is( join( ',', @{ $call->[2] || [] }, '|', @{ $call->[4] || [] } ), 'R,|,T',
    'a transcoder seek asks without mode I and with option T, as Song::open does' );

# Through the load itself: a Qobuz FLAC relayed (no direct stream) under
# Native files only.
$pp->client($c)->set( 'bitperfect', 1 ); $pp->client($c)->set( 'nativeonly', 1 );
{
    my $lc3 = FakeController->new;
    $c->controller($lc3);
    Slim::Utils::Timers::_reset();

    $Slim::Player::TranscodingHelper::ANSWER = { command => '-', streamformat => 'flc' };
    $lc3->{song} = FakeRelaySong->new;
    @sent = ();
    $c->play({ controller => $lc3 });
    is( $c->hqTier, '4', 'a Qobuz FLAC that LMS will not direct-stream goes through the relay' );
    is( $c->hqRelayNative, '1', 'recognised as a passthrough' );
    ok( scalar( grep { /PlaylistAdd/ } @sent ), 'and under Native files only it is PLAYED, not skipped' );
    is( $c->hqRefusedTier, '(undef)', 'nothing refused' );
    my $sig = Plugins::HQPlayerBridge::Plugin::signalPathFor( undef, { client => $c, instance => { ip => 'x' } } );
    is( $sig->{converted}, '0', 'the status does not mark it as converted' );
    ok( scalar( $sig->{tier} =~ /WITHOUT conversion/ ), 'and its route says relayed without conversion' );
    my %q; $PS->handler( $c, \%q );
    is( $q{hqp_checks}[3]{ok}, '1', 'the 4th check is a tick' );
    ok( scalar( $q{hqp_checks}[3]{text} =~ /without any conversion/ ), 'saying so' );

    $Slim::Player::TranscodingHelper::ANSWER = { command => '[flac] | [sox]', streamformat => 'flc' };
    @sent = ();
    $c->play({ controller => $lc3 });
    is( $c->hqRelayNative, '0', 'the same relay WITH a transcode is not native' );
    ok( scalar( !grep { /PlaylistAdd/ } @sent ), 'and is refused under Native files only' );
    Slim::Utils::Timers::_reset();

    # A hand-over resolving a converted next track must not change what the
    # PLAYING track's relay flag says.
    $c->hqTier(4); $c->hqRelayNative(1);
    $c->hqStarted(1); $c->hqPlayAck(1); $c->hqWanted('play');
    $c->_handOver( FakeRelaySong->new, undef );
    is( $c->hqRelayNative, '1', 'resolving the next track leaves the playing track\'s relay flag alone' );
    $c->hqNext(undef);
}
$pp->client($c)->set( 'bitperfect', 0 ); $pp->client($c)->set( 'nativeonly', 0 );

print "-- HTTP(S) streaming mode (1.3.0) --\n";
{
    my %q;
    $sp->set( 'useEnhancedHTTP', 0 );
    $PS->handler( $c, \%q );
    ok( scalar( !grep { $_->{text} =~ /Streaming mode for HTTP/ } @{ $q{hqp_checks} } ), 'Normal streaming: no line' );
    %q = ();
    $sp->set( 'useEnhancedHTTP', 1 );
    $PS->handler( $c, \%q );
    my ($h) = grep { $_->{text} =~ /Streaming mode for HTTP/ } @{ $q{hqp_checks} };
    ok( $h, 'Persistent mode: the page says why Qobuz is relayed' );
    is( $h && $h->{ok}, '2', 'as information, not a warning - the bytes are not changed' );
    $sp->set( 'useEnhancedHTTP', 0 );
}

printf "\n%d passed, %d failed\n",$pass,$fail;
exit($fail?1:0);
