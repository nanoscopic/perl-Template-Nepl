<header/>

<construct/>

use Digest::MD5 qw/md5_hex/;

sub init {
    $self->{'tags'} = {
        var => { sub => \&tpl_var, obj => $self },
        varq => { sub => \&tpl_varq, obj => $self },
        dest => { sub => \&tpl_dest, obj => $self },
        code => { sub => \&tpl_code, obj => $self },
        dump => { sub => \&tpl_dump, obj => $self }
    };
    my $tpl_pm_dir = $self->{'tpl_pm_dir'} = "/tmp/tpl_pm";
    $self->{'tpl_hash'} = {};
    $self->{'tpl_refs'} = {};
    $self->{'lang'} = 'perl';
    $self->load_cached_templates();
    
    if( ! -e $tpl_pm_dir ) {
        mkdir $tpl_pm_dir;
    }
}

sub tpl_dest( tag, in, out ) {
    <var self='lang'/>
    my $pageName = $tag->{'page'};
    if( $lang eq 'perl' ) {
        return "  $out .= \$mod_urls->genDest( page => '$pageName' );\n";
    }
    elsif( $lang eq 'js' ) {
        return "  $out += \$mod_urls.genDest( { page: '$pageName' } );\n";
    }
}

sub tpl_var( tag, in, out ) {
    <var self='lang'/>
    my $varName = $tag->{'name'};
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
    elsif( $lang eq 'js' ) {
        if( $varName eq 'else' ) {
            return "\n} else {\n";
        }
        if( $in eq '' || $tag->{'direct'} ) {
            return "  $out += $varName;\n";
        }
        else {
            return "  $out += ${in}.$varName;\n";
        }
    }
}
use Sub::Identify qw/sub_name/;
use Scalar::Util qw/blessed/;
sub dump( ob ) {
    my $className = blessed( $ob );
    return $className if( $className );
    my $rtype = ref( $ob );
    if( $rtype eq 'CODE' ) {
        return sub_name( $ob );
    }
    return substr( Dumper( $ob ), 8 );
}

sub tpl_dump( tag, in, out ) {
    <var self='lang'/>
    my $varName = $tag->{'name'};
    if( $lang eq 'perl' ) {
        if( $in eq '' || $tag->{'direct'} ) {
            return "  $out .= \$mod_templates->dump( \$$varName );\n";
        }
        else {
            return "  $out .= \$mod_templates->dump( ${in}{'$varName'} );\n";
        }
    }
    elsif( $lang eq 'js' ) {
        if( $in eq '' || $tag->{'direct'} ) {
            return "  out += \$mod_templates.dump( $varName );\n";
        }
        else {
            return "  $out += \$mod_templates.dump( ${in}.$varName );\n";
        }
    }
}

sub escape( str ) {
    use Data::Dumper;
    my $dump = Dumper( $str );
    my $res = substr( $dump, 8, -2 );
    $res =~ s/\n/'."\\n".'/g; # hackily inline carriage returns so that the code looks less messy
    $res =~ s/\.''$//; # strip trailing addition of empty string because it is pointless ( caused by previous line )
    return $res;
    #print "Input: $str\n";
    #print "output: $res\n";
}

sub escapeForJS( str ) {
    use Data::Dumper;
    my $dump = Dumper( $str );
    my $res = substr( $dump, 8, -2 );
    $res =~ s/\n/'+"\\n"+'/g; # hackily inline carriage returns so that the code looks less messy
    $res =~ s/\+''$//; # strip trailing addition of empty string because it is pointless ( caused by previous line )
    return $res;
    #print "Input: $str\n";
    #print "output: $res\n";
}

sub tpl_varq( tag, in, out ) {
    <var self='lang'/>
    my $varName = $tag->{'name'};
    my $valstr;
    if( $lang eq 'perl' ) {
        if( $in eq '' ) {
            $valstr = "\$$varName";
        }
        else {
            $valstr = "${in}{'$varName'}";
        }
        return "  $out .= \$mod_templates->escape( $valstr );\n";
    }
    if( $lang eq 'js' ) {
        if( $in eq '' ) {
            $valstr = "$varName";
        }
        else {
            $valstr = "${in}.$varName";
        }
        return "  $out += \$mod_templates.escape( $valstr );\n";
    }
}

sub tpl_code( tag, in, out ) {
    <var self='lang'/>
    my $data = $tag->{'data'};
    if( $data =~ m/^\+/ ) {
        $data = substr( $data, 1 );
        if( $lang eq 'perl' ) {
            return "  $out .= ($data);";
        }
        if( $lang eq 'js' ) {
            return "  $out += ($data);";
        }
    }
    return "$data\n";
}

sub register_tpl_tag( tplName, callback, callbackObj ) {
    $self->{'tags'}{ $tplName } = { sub => $callback, obj => $callbackObj };
}

sub run_tpl_tag( key, node, invar, outvar ) {
    my $callback = $self->{'tags'}{ $key };
    die "Invalid template tag $key" if( !$callback );
    my $sub = $callback->{'sub'};
    my $obj = $callback->{'obj'};
    return $sub->( $obj, $node, $invar, $outvar );
}

sub tag_template_tag {
    <tag name="template_tag" />
    #<param name="modXML" />
    <param name="metacode" var="tag" />
    #<param name="modInfo" />
    <param name="builder" />
    
    my $pageName = $tag->{'name'};
    my $subName = $builder->{'cursub'}{'name'};
    
    return [
        { action => 'add_var', self => 'mod_templates', var => 'tmpl' },
        { action => 'add_sub_text', sub => 'init', text => "\
            \$mod_templates->register_tpl_tag( '$pageName', \\&$subName, \$self );\
        " }
    ];
}

sub load_cached_templates {
    <var self="tpl_pm_dir" />
    
    return if( ! -e $tpl_pm_dir );
    opendir( my $dh, $tpl_pm_dir );
    my @files = readdir( $dh );
    closedir( $dh );
    
    for my $file ( @files ) {
        next if( $file =~ m/^\.+$/ );
        $self->load_cached_template( "$tpl_pm_dir/$file", $file );
    }
}

sub load_cached_template( path, file ) {
    <var self='tpl_refs' />
    <var self='lang' />
    
    require $path;
    if( $file =~ m/^tpl_(.+)_([A-Za-z0-9]+)$/ ) {
        my $id = $1;
        my $shortRef = $2;
        # Todo: Scan the file for the package name it uses
        my $ref = "TPL_${id}_$shortRef"->new();
        $tpl_refs->{ $shortRef } = 1;
        
        my $info = $ref->info();
        $info->{'ref'} = $ref;
        $info->{'loaded'} = 1;
        my $md5 = $info->{'md5'};
        
        my $tpls = $self->{'tpl_hash'};
        my $tpl_set = $tpls->{$id};
        if( !$tpl_set ) {
            $tpl_set = $tpls->{$id} = { id => $id, lang => $lang };
        }
        
        $tpl_set->{ $md5 } = $info;
    }   
}

sub fetch_template {
    <param name="lang"/>
    <param name="source"/>
    <param name="id"/>
    
    my $tpls = $self->{'tpl_hash'};
    my $tpl_set = $tpls->{$id};
    if( !$tpl_set ) {
        $tpl_set = $tpls->{$id} = { id => $id, lang => $lang };
    }
    
    my $md5 = md5_hex( $source );
    
    my $tpl = $tpl_set->{$md5};
    if( !$tpl ) {
        my $shortRef = $self->new_shortRef( $md5 );
        my $file;
        if( $lang eq 'perl' ) {
            $file = "tpl_${id}_$shortRef.pm";
        }
        if( $lang eq 'js' ) {
            $file = "tpl_${id}_$shortRef.js";
        }
        $tpl = $tpl_set->{$md5} = {
            file => $file,
            loaded => 0,
            ref => 0,
            generated => time(),
            shortRef => $shortRef,
            id => $id,
            md5 => $md5
        };
    }
    else {
        return $tpl;
    }
    
    if( $tpl->{'ref'} ) { # template is already loaded in memory ( for perl at least )
        return $tpl;
    }
    
    # template is not yet loaded
    
    # create the template pm file if needed
    my $filename = $tpl->{'file'};
    my $file = $self->{'tpl_pm_dir'} . '/' . $filename;
    my $shortRef = $tpl->{'shortRef'};
    #if( ! -e $file ) { 
        # TODO: Alter out var for JS in next line
        my $code;
        if( $lang eq 'perl' ) {
            $code = $self->template_to_code( $source, 0, 0, '$out', '$invar->' );
        }
        if( $lang eq 'js' ) {
            $code = $self->template_to_code( $source, 0, 0, 'out', 'invar' );
        }
        
        my $flatinfo = { %$tpl };
        delete $flatinfo->{'ref'};
        delete $flatinfo->{'loaded'};
        my $flatText;
        if( $lang eq 'perl' ) {
            $flatText = XML::Bare::Object::xml( 0, $flatinfo );
        }
        if( $lang eq 'js' ) {
            # use JSON encoding
        }
        
        my $out;
        if( $lang eq 'perl' ) {
            $out = "\
            package TPL_${id}_$shortRef;\
            use XML::Bare;\
            sub new {\
                my \$class = shift;\
                my \%params = \@_;\
                my \$self = bless {}, \$class;\
                return \$self;\
            }\
            sub info {\
                my ( \$ob, \$xml ) = XML::Bare::simple( text => " . $self->escape( $flatText ) . " );\
                return \$xml;\
            }\
            sub run {\
                my ( \$self, \$invar ) = \@_;\
                $code\
                return \$out;\
            }\
            1;\
            ";
        }
        if( $lang eq 'js' ) {
            # TODO
            $out = $code;
        }
        write_file( $file, $out );
    #}
      
    if( $lang eq 'perl' ) {
        require $file;
        $tpl->{'ref'} = "TPL_${id}_$shortRef"->new();
    }
    if( $lang eq 'js' ) {
        # TODO: possibly do lint checking against the JS file
        $tpl->{'ref'} = 1;
    }
    
    return $tpl;
}

sub new_shortRef( md5 ) {
    <var self='tpl_refs' />
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

sub tag_template {
    <var self='lang'/>
    <tag name="template" stage="normal2" type="raw" alias="tpl" />
    <param name="modXML" />
    <param name="metacode" var="tag" />
    <param name="modInfo" />
    <param name="ln" />

    my $invar;
    my $outvar = '';
    my $append = 0;
    if( exists $tag->{'append'} ) {
        $append = 1;
        if( my $out = $tag->{'out'} ) {
            if( $lang eq 'perl' ) {
                $outvar = "\$$out";
            }
            if( $lang eq 'js' ) {
                $outvar = "\$$out";
            }
        }
        else {
            $outvar = $self->{'prev_outvar'} || 'return';
        }
        
        if( my $in = $tag->{'in'} ) {
            $invar = '' if( $in eq 'direct' );
        }
    }
    else {
        my $in = $tag->{'in'} || '%_params';
        #my $invar;
        if( $in =~ m/^\%(.+)/ ) {
            my $name = $1;
            if( $lang eq 'perl' ) {
                $invar = "\$$name";
            }
            if( $lang eq 'js' ) {
                $invar = $name;
            }
        }
        elsif( $in =~ m/^\$(.+)/ ) {
            my $name = $1;
            if( $lang eq 'perl' ) {
                $invar = "\$${name}->";
            }
            if( $lang eq 'js' ) {
                $invar = $name;
            }
        }
        elsif( $in eq 'direct' ) {
            $invar = '';
        }
        else {
            if( $lang eq 'perl' ) {
                $invar = '$'.$in."->";
            }
            if( $lang eq 'js' ) {
                $invar = $in;
            }
        }
        #$self->{'in'} = $invar;
        
        my $out = $tag->{'out'} || 'return';
        #my $outvar = '';
        if( $lang eq 'perl' ) {
            if( $out eq 'return' ) {
                $outvar = '$out';
            }
            else {
                $outvar = "\$$out";
            }
        }
        if( $lang eq 'js' ) {
            if( $out eq 'return' ) {
                $outvar = '$out';
            }
            else {
                $outvar = "$out";
            }
        }
        #$self->{'outvar'} = $outvar;
    }
    if( ( ! defined $invar ) && defined $self->{'prev_invar'} ) {
        $invar = $self->{'prev_invar'};
    }
    
    if( ! defined $invar ) {
        print "Invar is not defined:\n";
        use Data::Dumper;
        die __FILE__ . "-" . __LINE__ . "-" . Dumper( $tag );
    }
    
    $self->{'prev_outvar'} = $outvar;
    $self->{'prev_invar'} = $invar;
    my $rawdata = $tag->{'raw'};
    $rawdata =~ s/||>/]]>/g; # undo hack added to builder to allow cdatas within raw tag blocks
    return $self->template_to_code( $tag->{'raw'}, $append, $ln, $outvar, $invar );
}

sub template_to_code( text, append, ln, outvar, invar ) {
    <var self='lang'/>
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
        
    my $out;
    if( $append ) {
        $out = '';
    }
    else {
        if( $lang eq 'perl' ) {
            $out = "my $outvar = '';\n";
        }
        if( $lang eq 'js' ) {
            $out = "var $outvar = '';\n";
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
            my ( $ob, $xml ) = XML::Bare->simple( text => $part );
            $part =~ s/\n/ -- /g; # strip carriage returns so xml can be shown on one line
            $part =~ s/]]>/ ]!]>/g;
            if( $lang eq 'js' ) {
                $out .= "  // XML: $part //\@$partLn\n";
            }
            if( $lang eq 'perl' ) {
                $out .= "  # XML: $part #\@$partLn\n";
            }
            for my $key ( keys %$xml ) {
                my $node = $xml->{ $key };
                $out .= $self->run_tpl_tag( $key, $node, $invar, $outvar );
            }
        }
        else {
            if( $lang eq 'perl' ) {
                $out .= "  $outvar .= " . $self->escape( $part ) .";\n";
            }
            if( $lang eq 'js' ) {
                $out .= "  $outvar += " . $self->escapeForJS( $part ) .";\n";
            }
        }
    }
    
    if( $outvar eq 'return' ) {
        $out .= "return $outvar;\n";
    }
    
    #print "As code: " . Dumper( $out );
    return $out;
}