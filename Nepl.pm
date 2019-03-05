# Copyright (C) 2017,2019 David Helkowski
# Original code from https://github.com/nanoscopic/lumith_builder/blob/master/source_core/Templates.pm
# License AGPL

package Template::Nepl;

use Digest::MD5 qw/md5_hex/;
use Sub::Identify qw/sub_name/;
use Scalar::Util qw/blessed/;
use Data::Dumper;
use Parse::XJR;

sub new {
    my $class = shift;
    my %params = @_;
    my $self = bless {}, $class;
    $self->init(%params);
    return $self;
}

sub init {
    my $self = shift;
    my %params = ( @_ );
    $self->{'tags'} = {
        var => { sub => \&tpl_var, obj => $self },
        varq => { sub => \&tpl_varq, obj => $self },
        code => { sub => \&tpl_code, obj => $self },
        dump => { sub => \&tpl_dump, obj => $self }
    };
    my $tpl_pm_dir = $self->{'tpl_pm_dir'} = "/tmp/tpl_pm";
    $self->{'tpl_hash'} = {};
    $self->{'tpl_refs'} = {};
    $self->{'lang'} = $params{'lang'} || 'perl';
    $self->{'pkg'} = $params{'pkg'} || '';
    
    if( ! -e $tpl_pm_dir ) {
        mkdir $tpl_pm_dir;
    }
}

sub tpl_var {
    my ( $self, $tag, $in, $out ) = @_;
    my $lang = $self->{'lang'};
    
    my $varName = $tag->{'name'}->value();
    if( $lang eq 'perl' ) {
        if( $varName eq 'else' ) {
            return "\n} else {\n";
        }
        if( $in eq '' || $tag->{'direct'} ) {
            return "  $out .= \$$varName;\n";
        }
        else {
            return "  $out .= ${in}{'$varName'};\n";
        }
    }
}

sub dump {
    my $ob = shift;
    
    my $className = blessed( $ob );
    return $className if( $className );
    my $rtype = ref( $ob );
    if( $rtype eq 'CODE' ) {
        return sub_name( $ob );
    }
    return substr( Dumper( $ob ), 8 );
}

sub tpl_dump {
    my ( $self, $tag, $in, $out ) = @_;
    my $lang = $self->{'lang'};
    
    my $varName = $tag->{'name'}->value();
    if( $lang eq 'perl' ) {
        if( $in eq '' || $tag->{'direct'} ) {
            return "  $out .= Template::Nepl::dump( '$lang', \$$varName );\n";
        }
        else {
            return "  $out .= Template::Nepl::dump( '$lang', ${in}{'$varName'} );\n";
        }
    }
}

sub escape {
    my $str = shift;
    
    my $dump = Dumper( $str );
    my $res = substr( $dump, 8, -2 );
    $res =~ s/\n/'."\\n".'/g; # hackily inline carriage returns so that the code looks less messy
    $res =~ s/\.''$//; # strip trailing addition of empty string because it is pointless ( caused by previous line )
    return $res;
}

sub tpl_varq {
    my ( $self, $tag, $in, $out ) = @_;
    my $lang = $self->{'lang'};
    
    my $varName = $tag->{'name'}->value();
    my $valstr;
    if( $lang eq 'perl' ) {
        if( $in eq '' ) {
            $valstr = "\$$varName";
        }
        else {
            $valstr = "${in}{'$varName'}";
        }
        return "  $out .= Template::Nepl::escape( $valstr );\n";
    }
}

sub tpl_code {
    my ( $self, $tag, $in, $out ) = @_;
    my $lang = $self->{'lang'};
    
    my $data = $tag->{'data'}->value();
    if( $data =~ m/^\+/ ) {
        $data = substr( $data, 1 );
        if( $lang eq 'perl' ) {
            return "  $out .= eval {$data};";
        }
    }
    return "$data\n";
}

sub run_tpl_tag {
    my ( $self, $key, $node, $invar, $outvar ) = @_;
    
    my $callback = $self->{'tags'}{ $key };
    die "Invalid template tag $key" if( !$callback );
    my $sub = $callback->{'sub'};
    my $obj = $callback->{'obj'};
    return $sub->( $obj, $node, $invar, $outvar );
}

sub fetch_template {
    my $self = shift;
    my %params = ( @_ );
    my $lang   = $self->{'lang'};
    my $source = $params{'source'};
    
    my $tpls = $self->{'tpl_hash'};
    
    my $tpl;
    if( defined $params{'id'} ) {
        my $id  = $params{'id'};
        my $tpl = $tpls->{$id};
        return $tpl if( $tpl );
        $tpl = $tpls->{$id} = { id => $id, lang => $lang, shortRef => $id };
    }
    else {
        my $md5 = md5_hex( $source );
        $tpl = $tpl_set->{$md5};
        return $tpl if( $tpl );
        my $shortRef = $self->new_shortRef( $md5 );
        $tpl = $tpls->{$md5} = { id => $md5, lang => $lang, shortRef => $shortRef };
    }
        
    if( $lang eq 'perl' ) {
        $tpl->{'code'} = $self->template_to_code( $source, 0, 0, '$out', '$invar->' );
    }
      
    return $tpl;
}

sub new_shortRef {
    my ( $self, $md5 ) = @_;
    my $tpl_refs = $self->{'tpl_refs'};
    
    my $len = length( $md5 );
    for( my $i=1;$i<=$len;$i++ ) {
        my $part = substr( $md5, 0, $i );
        if( !$tpl_refs->{ $part } ) {
            $tpl_refs->{ $part } = 1;
            return $part;
        }
    }
    return $md5;
}

sub template_to_code {
    my ( $self, $text, $append, $ln, $outvar, $invar ) = @_;
    my $lang = $self->{'lang'};
    
    $text =~ s/\*<(.+?)>\*/\%\%\%*<$1>\%\%\%/g; # Split out *<>* tags
    $text =~ s/\*\{([a-zA-Z0-9_]+)\}/\%\%\%*<var name='$1'\/>\%\%\%/g; # *{[word]} vars ( named template variable )
    $text =~ s/\*\{\$([a-zA-Z0-9_]+)\}/\%\%\%*<var name='$1' direct=1\/>\%\%\%/g; # *{$[word]} vars ( "direct" local variable usage )
    $text =~ s/\*\{\!([a-zA-Z0-9_]+)\}/\%\%\%*<dump name='$1'\/>\%\%\%/g; # *{![word]}
    $text =~ s/\*\{['"]{1,2}([a-zA-Z0-9_]+)\}/\%\%\%*<varq name='$1'\/>\%\%\%/g; # *{''[word]} vars ( they are put in a string )
    $text =~ s|\*\{if (.+?)\}|\%\%\%*<code><data><![CDATA[if($1){\n]]></data></code>\%\%\%|gs; # *{if [perl if expr]}
    $text =~ s|\*\{/if\}|\%\%\%*<code><data>}\n</data></code>\%\%\%|gs; # *{/if}
    $text =~ s|\*\{(.+?)\}\*|\%\%\%*<code><data><![CDATA[$1]]></data></code>\%\%\%|gs; # *{[perl code]}*
    $text =~ s/(\%\%\%)+/\%\%\%/g; # ensure magic sequence doesn't repeat multiple times in a row
    
    my @lines = split(/\n/,$text);
    my @lines2 = '';
    my $i = 0;
    for my $line ( @lines ) {
        my $lnOff = $ln + $i;
        #print "Line: $line---$lnOff\n";
        push( @lines2, "$line---$lnOff" );
        $i++;
    }
    $text = join("\n",@lines2);
    
    #print "Split up text of template:\n";
    #use Data::Dumper;
    #print Dumper( $text );
    #my $outvar = $self->{'outvar'};
        
    my $out = '';
    if( $lang eq 'perl' && $self->{'pkg'} ) {
        my $pkg = $self->{'pkg'};
        $out .= "package $pkg;use strict;\n";
    }
    if( $append ) {
        #$out = '';
    }
    else {
        if( $lang eq 'perl' ) {
            $out .= "my $outvar = '';\n";
        }
    }
    my $curLn = $ln;
    my @parts = split( '%%%', $text );
    for my $part ( @parts ) {
        my $partLnMin = 9999;
        my $partLnMax = 0;
        my $partLn = '?';
        #use Data::Dumper;
        #print Dumper( $part );
        if( $part =~ m/---([0-9]+)(\n|$)/ ) {
            while( $part =~ m/---([0-9]+)(\n|$)/g ) {
                my $aLn = $1;
                if( $aLn > $curLn ) {
                    $curLn = $aLn;
                }
                #print "aLn: $aLn\n";
                if( $aLn < $partLnMin ) {
                    $partLnMin = $aLn;
                }
                if( $aLn > $partLnMax ) {
                    $partLnMax = $aLn;
                }
            }
            $part =~ s/---[0-9]+(\n|$)/$1/g;
        }
        if( $partLnMin == $partLnMax ) {
            $partLn = $partLnMin;
        }
        else {
            if( $partLnMin == 9999 && $partLnMax == 0 ) {
                $partLn = $curLn;
            }
            else {
                $partLn = "$partLnMin-$partLnMax";
            }
        }
        if( $part =~ m/^\*</ ) {
            $part = substr( $part, 1 ); # strip off initial *
            my $root = Parse::XJR->new( text => $part );
            $part =~ s/\n/ -- /g; # strip carriage returns so xml can be shown on one line
            $part =~ s/]]>/ ]!]>/g;
            if( $lang eq 'perl' ) {
                $out .= "  # XML: $part #\@$partLn\n";
            }
            my $curNode = $root->firstChild();
            while( $curNode ) {
                my $key = $curNode->name();
                $out .= $self->run_tpl_tag( $key, $curNode, $invar, $outvar );
                $curNode = $curNode->next();
            }
        }
        else {
            if( $lang eq 'perl' ) {
                $out .= "  $outvar .= " . Template::Nepl::escape( $part ) .";\n";
            }
        }
    }
    
    if( $outvar eq 'return' ) {
        $out .= "return $outvar;\n";
    }
    $out .= "$outvar;";
    #print "As code: " . Dumper( $out );
    return $out;
}

1;