package Plugins::HQPlayerBridge::PlayerSettings;

# THE PLAYER'S OWN "HQPlayer" PAGE (1.1.0) - Player settings -> HQPlayer.
#
# WHY A PAGE OF ITS OWN, NOT MORE ROWS ON LMS'S AUDIO PAGE. LMS builds the
# Audio page from the player's capability methods (Slim::Web::Settings::Player::
# Audio::prefs), and almost every row it can show - bass, treble, balance,
# polarity, rolloff, output channels, crossfade - is a Squeezebox's own DSP or
# DAC hardware. Here HQPlayer fetches the music ITSELF; LMS has no audio stage
# to apply those to, so declaring them would put controls on screen that do
# nothing. What this player CAN guarantee is that nothing on LMS's side alters
# the stream, and that is what this page is for.
#
# Two switches, decided in Perl as RADIO GROUPS (the fleet rule - see
# Settings.pm: exactly one option checked in every state, never a <select>,
# never a bare checkbox that posts nothing when off):
#
#   bitperfect  - Player::applyBitPerfect, run from Plugin::_bitPerfectChanged
#                 on the save, so a `pref` command behaves the same;
#   nativeonly  - only read while bitperfect is on (Player::nativeOnly).
#
# The status half is a SNAPSHOT drawn at page load, on purpose: a self-polling
# settings page never refreshed inside Material (see Live.pm's header), so
# this page does not poll and links to the live view for that instead.
#
# This module calls nothing in Plugin.pm: the status rows come through the
# source Plugin hands in at init (setStatusSource), the same shape as
# Addresses::init - see the trap at the top of Live.pm.

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Strings;

use Plugins::HQPlayerBridge::Settings;
use Plugins::HQPlayerBridge::Player;     # tierConverts    # statusLines - one formatter, two pages

my $prefs       = preferences('plugin.hqplayerbridge');
my $serverPrefs = preferences('server');

my $statusSource;

sub setStatusSource { $statusSource = $_[-1]; return }

sub name { Slim::Web::HTTP::CSRF->protectName('PLUGIN_HQPLAYER_PLAYER_SETTINGS') }

sub page { Slim::Web::HTTP::CSRF->protectURI('plugins/HQPlayerBridge/settings/player.html') }

sub needsClient { 1 }

# Listed in a player's settings ONLY for our own players. Base handler()
# also redirects to Basic for any other player that reaches the URL.
sub validFor {
    my ( $class, $client ) = @_;
    return ( $client && $client->isa('Plugins::HQPlayerBridge::Player') ) ? 1 : 0;
}

sub prefs {
    my ( $class, $client ) = @_;
    return ( $prefs->client($client), qw(bitperfect nativeonly) );
}

sub handler {
    my ( $class, $client, $params, @args ) = @_;

    if ( $params->{saveSettings} ) {

        # A partial POST (no sentinel) changes nothing - the base class would
        # otherwise store undef for both switches and turn the mode off.
        if ( !defined $params->{hqp_player_form} ) {
            $params->{"pref_$_"} = $prefs->client($client)->get($_) for qw(bitperfect nativeonly);
        }
        else {
            # "1" or "0", and anything else (nothing posted included) is OFF.
            for my $p (qw(bitperfect nativeonly)) {
                $params->{"pref_$p"} = ( ( $params->{"pref_$p"} // '' ) eq '1' ) ? 1 : 0;
            }
        }
    }

    return $class->SUPER::handler( $client, $params, @args );
}

# After the save, before the page is drawn - so the radios show what was SAVED.
sub beforeRender {
    my ( $class, $params, $client ) = @_;

    return unless $client;

    my $cp = $prefs->client($client);
    my $sp = $serverPrefs->client($client);
    my $s  = sub { Slim::Utils::Strings::string(@_) };

    $params->{hqp_bp}     = $cp->get('bitperfect') ? 1 : 0;
    $params->{hqp_native} = $cp->get('nativeonly') ? 1 : 0;

    # THE CHECKS - each LMS-side thing that could alter the stream, read from
    # where LMS itself reads it, with whether it is clean. Formatted HERE; the
    # template only prints finished strings (the Settings.pm rule).
    my @checks;
    my $add = sub { push @checks, { ok => $_[0] ? 1 : 0, text => $_[1] } };

    my $rg = $sp->get('replayGainMode') || 0;
    $add->( $params->{hqp_bp} || !$rg,
          $params->{hqp_bp} ? $s->('PLUGIN_HQPLAYER_BP_CHK_RG_UNITY')
        : $rg               ? $s->('PLUGIN_HQPLAYER_BP_CHK_RG_ON')
        :                     $s->('PLUGIN_HQPLAYER_BP_CHK_RG_OFF') );

    my $max = $sp->get('maxBitrate');
    $add->( defined $max && $max eq '0',
        ( defined $max && $max eq '0' )
            ? $s->('PLUGIN_HQPLAYER_BP_CHK_RATE_OK')
            : sprintf( $s->('PLUGIN_HQPLAYER_BP_CHK_RATE_CAP'), defined $max ? $max : '?' ) );

    my $dvc   = $sp->get('digitalVolumeControl');
    my $fixed = defined $dvc && !$dvc;
    $add->( $fixed, $fixed ? $s->('PLUGIN_HQPLAYER_BP_CHK_VOL_FIXED') : $s->('PLUGIN_HQPLAYER_BP_CHK_VOL_VAR') );

    # 4. THE ROUTE OF THE LAST TRACK (1.1.1) - not a setting but the fact the
    # three above exist to protect: did Lyrion itself touch the bytes of the
    # track HQPlayer is playing, or last played? hqTier is set at every load
    # and kept after a stop. ok => 2 is NEUTRAL (nothing to judge yet).
    my $tier = $client->can('hqTier') ? ( $client->hqTier || 0 ) : 0;

    if ( $client->can('hqRefusedTier') && defined $client->hqRefusedTier ) {
        $add->( 1, $s->('PLUGIN_HQPLAYER_BP_CHK_ROUTE_SKIPPED') );
    }
    elsif ( !$tier ) {
        push @checks, { ok => 2, text => $s->('PLUGIN_HQPLAYER_BP_CHK_ROUTE_NONE') };
    }
    else {
        $add->( !Plugins::HQPlayerBridge::Player::tierConverts($tier),
            $s->( 'PLUGIN_HQPLAYER_BP_CHK_ROUTE_' . $tier ) );
    }

    $params->{hqp_checks} = \@checks;

    # THIS player's row from the shared status source - the same strings the
    # Apps feed and the live view show.
    my $rows = $statusSource ? eval { $statusSource->($client) } : undef;
    my ($mine) = grep { ( $_->{playerid} // '' ) eq $client->id } @{ ( $rows || {} )->{rows} || [] };

    $params->{hqp_status} = $mine ? Plugins::HQPlayerBridge::Settings::statusLines( $mine->{path} ) : [];

    return;
}

1;
