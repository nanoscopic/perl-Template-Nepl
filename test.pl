#!/usr/bin/perl -w
use strict;
use lib '.';
use Template::Nepl;
use Template::pkg;

my $nepl = Template::Nepl->new( lang => 'perl', pkg => 'Template::pkg' );

my $source = "a *{if func()}blah*{/if} c";
my $b = 2;
my $tpl = $nepl->fetch_template( source => $source );

my $code = $tpl->{'code'};
print "Code:\n$code\n";
my $out = eval( $code );
if( $@ ) {
    print "$@\n";
}
print "out: $out\n";
