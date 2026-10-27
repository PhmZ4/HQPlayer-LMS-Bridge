package Slim::Player::TranscodingHelper;

# Stands in for LMS's transcoding table. The real getConvertCommand2(
# $song, $type, \@streamModes, \@need, \@want ) returns the chosen rule as a
# hash - `command` is the literal '-' for the passthrough rule (convert.conf
# `flc flc * *`). A test parks the answer here, and the call is recorded so a
# test can see the same question Song::open asks was asked.
our ( $ANSWER, @CALLS );
sub getConvertCommand2 {
    push @CALLS, [ @_ ];
    return ref $ANSWER eq 'CODE' ? $ANSWER->(@_) : $ANSWER;
}
1;
