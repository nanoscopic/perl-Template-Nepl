#!/usr/bin/perl
use ExtUtils::MakeMaker;
require 5.006;
my @basics = ( 
    AUTHOR       => 'David Helkowski <cpan@codechild.com>',
    ABSTRACT     => 'Templating system with embedded scripting',
    NAME         => 'Template::Nepl',
    VERSION_FROM => 'Nepl.pm',
    BUILD_REQUIRES => {
        'English' => 0
    },
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '6.30'
    },
    PREREQ_PM => {
        Carp => 0,
        Exporter => 0
    }
);

if( $ExtUtils::MakeMaker::VERSION >= 6.31 ) {
  push( @basics, LICENSE => 'perl' );
}

WriteMakefile( @basics );