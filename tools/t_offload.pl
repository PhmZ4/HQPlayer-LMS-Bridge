# GPU offload on the live page (1.4.0): read from HQPlayer's own log (:8088/log),
# because the 4321 control API has nothing about it.
use strict; use warnings;
BEGIN { package main; use constant DEBUGLOG=>0; use constant INFOLOG=>0; use constant WEBUI=>1; }
use lib '.';

require Slim::Utils::Strings;
{
    no warnings qw(redefine once);
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
require Plugins::HQPlayerBridge::Live;

my ($pass,$fail)=(0,0);
sub is { my($got,$want,$name)=@_; $got//='(undef)'; $want//='(undef)';
  if ($got eq $want){$pass++; printf "  ok   %s\n",$name}
  else {$fail++; printf "  FAIL %s\n        got: %s\n       want: %s\n",$name,$got,$want} }
sub ok { my $n = pop; my $c = @_ ? $_[0] : 0;
  $c ? ($pass++, printf "  ok   %s\n",$n) : ($fail++, printf "  FAIL %s\n",$n) }

my $P = \&Plugins::HQPlayerBridge::Plugin::_parseOffload;

# A real engine start (HQPlayer Embedded 6.3.3, Linux, RTX 4070), trimmed.
my $start = <<'LOG';
  2026/11/27 19:12:22  asoundlib version: 1.2.15.3
  2026/11/27 19:12:23 CUDA offload requested
  2026/11/27 19:12:23 ROCm/HIP offload requested
  2026/11/27 19:12:23 MP3 decoders:
  2026/11/27 19:12:23 	AVX
  2026/11/27 19:12:23 libDSP version 39.0.0
  2026/11/27 19:12:23 HQPlayer Engine version 6.3.3
  2026/11/27 19:12:23 Core pinning enabled
  2026/11/27 19:12:23 CUDA offload: all
  2026/11/27 19:12:23 CUDA devices:
  2026/11/27 19:12:23 	0: NVIDIA GeForce RTX 4070
  2026/11/27 19:12:23 Using 16 block count
& 2026/11/27 19:12:23 Convolution disabled
% 2026/11/27 19:12:23 ...configuration reloaded
LOG

print "-- parsing --\n";
my $r = $P->($start);
is( $r->{state}, 'ok', 'offload in use: ok' );
is( $r->{mode}, 'all', 'the mode' );
is( $r->{api}, 'CUDA', 'the API' );
is( join('|', @{ $r->{devices} }), 'NVIDIA GeForce RTX 4070', 'the GPU' );

my $requested_only = <<'LOG';
  2024/10/01 19:02:24 asoundlib version: 1.2.11
  2024/10/01 19:02:24 CUDA offload requested
  2024/10/01 19:02:24 ROCm/HIP offload requested
  2024/10/01 19:02:24 MP3 decoders:
  2024/10/01 19:02:24 HQPlayer Engine version 5.8.2
  2024/10/01 19:02:24 Using 16 block count
LOG
is( $P->($requested_only)->{state}, 'fail', 'requested, never used: fail' );

my $none = <<'LOG';
  2026/11/27 19:12:22  asoundlib version: 1.2.15.3
  2026/11/27 19:12:23 MP3 decoders:
  2026/11/27 19:12:23 HQPlayer Engine version 6.3.3
  2026/11/27 19:12:23 Core pinning enabled
LOG
is( $P->($none)->{state}, 'off', 'nothing about a GPU: off' );

is( $P->($start . $none)->{state}, 'off', 'the NEWEST start speaks, not an older one' );
is( $P->($none . $start)->{state}, 'ok',  'CONTROL: newest is the GPU start' );

my $devless = $start; $devless =~ s/^.*0: NVIDIA.*\n//m;
is( $P->($devless)->{state}, 'fail', 'offload line but no device: fail' );

ok( !defined $P->("garbage\nno engine here\n"), 'no engine start: undef' );
ok( !defined $P->(''), 'empty log: undef' );

my $html = "<html><body><pre>" . join( "<br>", map { s/&/&amp;/gr } split /\n/, $start ) . "</pre></body></html>";
is( $P->($html)->{state}, 'ok', 'an HTML-wrapped log parses the same' );

print "-- the fetch --\n";
# Drive _readOffload through the package's %bridges via signalPathFor's helper.
{
    package FakeC; sub connected { 1 }
}
Slim::Networking::SimpleAsyncHTTP::_reset();
my $b = { instance => { ip => '10.0.0.9' }, control => bless( {}, 'FakeCtl' ), client => bless( {}, 'FakeC' ) };
Plugins::HQPlayerBridge::Plugin::_bridgesRef()->{x} = $b;
Plugins::HQPlayerBridge::Plugin::_offloadTimer('x');
my %g = Plugins::HQPlayerBridge::Plugin::offloadFor( undef, $b );
is( scalar @Slim::Networking::SimpleAsyncHTTP::REQ, 1, 'a proven link asks for the log once' );
is( $Slim::Networking::SimpleAsyncHTTP::REQ[0]{url}, 'http://10.0.0.9:8088/log', 'at :8088/log' );
ok( !%g, 'nothing shown before the answer' );

{ package FakeRes; sub content { $_[0]{c} } }
$Slim::Networking::SimpleAsyncHTTP::REQ[0]{cb}->( bless { c => $start }, 'FakeRes' );
%g = Plugins::HQPlayerBridge::Plugin::offloadFor( undef, $b );
is( $g{gpu_state}, 'ok', 'state after the answer' );
is( $g{gpu}, 'CUDA all - NVIDIA GeForce RTX 4070', 'the text shown' );

$Slim::Networking::SimpleAsyncHTTP::REQ[0]{ecb}->();
%g = Plugins::HQPlayerBridge::Plugin::offloadFor( undef, $b );
is( $g{gpu_state}, 'unknown', 'no web interface: unknown (grey)' );

Slim::Networking::SimpleAsyncHTTP::_reset();
{
    my $pl = do { local $/; open my $f, '<', '../HQPlayerBridge/Plugin.pm' or die; <$f> };
    my ($sp) = $pl =~ /(sub signalPathFor \{.*?\n\}\n)/s;
    my ($tl) = $pl =~ /(sub topLevel \{.*?\n\}\n)/s;
    my ($sq) = $pl =~ /(sub _signalPathQuery \{.*?\n\}\n)/s;
    ok( $sp && $sp !~ /_readOffload|_offloadTimer/, 'signalPathFor never fetches' );
    ok( $tl && $tl !~ /_readOffload|_offloadTimer/, 'the Apps feed never fetches' );
    ok( $sq && $sq !~ /_readOffload|_offloadTimer/, 'the live poll never fetches - only a proven link does' );
    my ($lp) = $pl =~ /(sub _onLinkProven \{.*?\n\}\n)/s;
    ok( $lp && $lp =~ /setTimer\( \$id, .*\\&_offloadTimer/, 'a proven link schedules the read' );
}
print "-- the page --\n";
my $src = do { local $/; open my $f, '<', '../HQPlayerBridge/Live.pm' or die; <$f> };
ok( $src =~ /html \+= lamp\(L\.gpu, b\.gpu, b\.gpu_state\)/, 'the page draws the lamp' );
ok( $src =~ /\.lamp\.ok \{ background: var\(--ok\)/, 'green when ok' );
ok( $src =~ /\.lamp\.bad \{ background: var\(--bad\)/, 'red when off or failed' );

print "\n$pass passed, $fail failed\n";
exit( $fail ? 1 : 0 );
