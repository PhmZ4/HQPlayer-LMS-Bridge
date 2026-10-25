# HQPlayer's input and output buffers on the live page (1.2.0).
#
#   * Player.pm keeps input_fill / output_fill off every <Status/> push, 0
#     included (a 0 is the most important reading there is).
#   * Plugin::signalPathFor answers a finished string AND a 0-100 number, so
#     the page sizes the bar without parsing the string.
#   * The served page draws a bar per buffer, red only when LOW WHILE PLAYING.
#     That last part RUNS the page's own bar() under node when node exists.
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
# see the note on ok() in t_player.pl - a failed match returns the EMPTY LIST
sub ok { my $n = pop; my $c = @_ ? $_[0] : 0;
  $c ? ($pass++, printf "  ok   %s\n",$n) : ($fail++, printf "  FAIL %s\n",$n) }

print "-- the unit --\n";
my $P = \&Plugins::HQPlayerBridge::Plugin::_fillPct;
is( $P->('0.73'),  '73',  'a fraction, as HQPlayer sends it, reads as a percentage' );
is( $P->('0'),     '0',   'an empty buffer is 0, not missing' );
is( $P->('1'),     '100', 'a full one is 100' );
is( $P->('0.005'), '1',   'rounded, not truncated' );
is( $P->('73'),    '73',  'a figure already in percent is not multiplied again' );
is( $P->('140'),   '100', 'clamped at 100' );
is( $P->('-0.2'),  '0',   'and at 0' );
is( $P->('n/a'),   '(undef)', 'a non-number is no reading at all' );
is( $P->(undef),   '(undef)', 'nor is nothing' );

print "-- the player keeps both off the status push --\n";
my $c = Plugins::HQPlayerBridge::Player->new('02:cc:00:00:00:01', 'paddr', 1.0, undef, 12, undef);
{
    package FakeController;
    sub new { bless {}, shift }
    sub AUTOLOAD { return }    # every controller callback is a no-op here
    sub isPaused { 0 } sub isStopped { 1 } sub isPlaying { 0 }
}
$c->controller( FakeController->new );
{
    no warnings qw(redefine once);
    local *Plugins::HQPlayerBridge::Player::_followVolume = sub {};
    eval { $c->_onStatus( { state => 0, input_fill => '0.81', output_fill => '0' }, '<Status/>' ) };
    print "  note _onStatus died: $@" if $@;
}
is( $c->hqPath->{input_fill},  '0.81', 'input_fill is kept' );
is( $c->hqPath->{output_fill}, '0',    'and output_fill, a 0 included - defined, not true' );

print "-- the signal path answers a string and a number --\n";
my $sig = Plugins::HQPlayerBridge::Plugin::signalPathFor( undef,
    { client => $c, instance => { ip => '192.168.1.20' } } );
is( $sig->{in_fill},  '81 %', 'the input buffer as a finished string' );
is( $sig->{in_pct},   '81',   'and as a number for the bar' );
is( $sig->{out_fill}, '0 %',  'an empty output buffer is still reported' );
is( $sig->{out_pct},  '0',    'as 0' );

$c->hqPath->{output_fill} = 'junk';
$sig = Plugins::HQPlayerBridge::Plugin::signalPathFor( undef,
    { client => $c, instance => { ip => '192.168.1.20' } } );
ok( !exists $sig->{out_fill} && !exists $sig->{out_pct}, 'a reading that is not a number draws no row' );

{
    open my $fh, '<', '../HQPlayerBridge/Plugin.pm' or die $!;
    my $src = do { local $/; <$fh> };
    ok( scalar( $src =~ /in_fill in_pct out_fill out_pct/ ), 'the signalpath query sends all four' );
}

print "-- the live page draws them --\n";
our $SENT;
{
    package FakeResponse;
    sub new { bless { headers => {} }, shift }
    sub code { my $s=shift; $s->{code} = shift if @_; $s->{code} }
    sub content_type { my $s=shift; $s->{ct} = shift if @_; $s->{ct} }
    sub header { my ($s,$k,$v)=@_; $s->{headers}{lc $k} = $v if defined $v; $s->{headers}{lc $k} }
    sub content_length { my $s=shift; $s->{len} = shift if @_; $s->{len} }
    package FakeHttpClient;
    sub new { bless {}, shift } sub connected { 1 }
}
{
    no warnings qw(redefine once);
    *Slim::Web::HTTP::addHTTPResponse = sub { $SENT = ${ $_[2] }; return };
}
Plugins::HQPlayerBridge::Live->init('9.9.9');
Plugins::HQPlayerBridge::Live::_handler( FakeHttpClient->new, FakeResponse->new );

ok( scalar( $SENT =~ /inbuf:\s+"Input buffer"/ && $SENT =~ /outbuf:\s+"Output buffer"/ ), 'both labels are served, localised' );
ok( scalar( $SENT =~ /bar\(L\.inbuf,\s+b\.in_fill,\s+b\.in_pct,/ ), 'the input buffer row is drawn' );
ok( scalar( $SENT =~ /bar\(L\.outbuf, b\.out_fill, b\.out_pct,/ ), 'and the output one' );
ok( scalar( $SENT =~ /\.buf\.low > i \{ background: var\(--bad\)/ ), 'a low buffer has its own colour' );
ok( scalar( $SENT !~ /\\/ ), 'the served script holds no backslash for Perl to eat (the Live.pm heredoc trap)' );

my $node = `which node 2>/dev/null`; chomp $node;
if ( !$node ) {
    print "  skip no node here - bar() is only source-checked\n";
}
else {
    my ($esc) = $SENT =~ /(function esc\(.*?\n    \})/s;
    my ($bar) = $SENT =~ /(var BUF_LOW = \d+;\s*function bar\(.*?\n    \})/s;
    ok( $esc && $bar, 'esc() and bar() are found in the served page' );

    my $js = ( $esc // '' ) . "\n" . ( $bar // '' ) . q{
var out = [];
out.push(bar('In', '73 %', 73, true));
out.push(bar('In', '5 %', 5, true));
out.push(bar('In', '5 %', 5, false));
out.push(bar('In', '', 50, true));
out.push(bar('In', '140 %', 140, true));
out.push(bar('In', '<x>', 50, false));
console.log(JSON.stringify(out));
};
    my $f = ( $ENV{TMPDIR} || '/tmp' ) . "/hqp_bar_$$.js";
    open my $fh, '>', $f or die $!; print $fh $js; close $fh;
    my $res = `$node $f 2>&1`; unlink $f;
    my @o = eval { @{ JSON::PP->new->decode($res) } };
    require JSON::PP;
    @o = @{ JSON::PP->new->decode($res) } if !@o && $res =~ /^\[/;

    ok( scalar( ( $o[0] // '' ) =~ /width:73%/ && $o[0] !~ /low/ ), 'a healthy buffer while playing: a bar 73% wide, not low' );
    ok( scalar( ( $o[1] // '' ) =~ /class="buf low"/ && $o[1] =~ /bufn bad/ ), 'under 15% WHILE PLAYING is low, bar and figure' );
    ok( scalar( ( $o[2] // '' ) !~ /low|bad/ ), 'the same 5% stopped or paused is just idle' );
    is( $o[3] // 'missing', '', 'no reading, no row' );
    ok( scalar( ( $o[4] // '' ) =~ /width:100%/ ), 'a bar never outgrows its track' );
    ok( scalar( ( $o[5] // '' ) =~ /&lt;x&gt;/ ), 'the figure is escaped' );
}

printf "\n%d passed, %d failed\n",$pass,$fail;
exit($fail?1:0);
