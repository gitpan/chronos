# $Id: Makefile.PL,v 1.9 2002/07/11 13:19:08 nomis80 Exp $
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'         => 'Chronos',
    'VERSION_FROM' => 'Chronos.pm',    # finds $VERSION
    'PREREQ_PM'    => {
        'Apache::DBI'       => 0,
        'DBI'               => 0,
        'DBD::mysql'        => 0,
        'Apache::Constants' => 0,
        'Apache'            => 0,
        'Date::Calc'        => 0,
        'Apache::Request'   => 0,
        'HTML::Entities'    => 0,
    },                                 # e.g., Module::Name => 1.1
    'EXE_FILES' => [ grep { -f } <scripts/*> ],
);

sub MY::install {
    package MY;
    my $inherited = shift->SUPER::install(@_);
    $inherited =~ s/^(install ::.*)/$1 lang_install html_install startup_install/m;
    $inherited =~ s/^(uninstall ::.*)/$1 lang_uninstall html_uninstall startup_uninstall/m;
    return $inherited;
}

sub MY::postamble {
    my $langfiles = join " ", grep { -f } <lang/*>;
    my @html_files = grep { -f } <html/*>;
    my $html_files = join " ", @html_files;
    s/html\/// foreach @html_files;
    my $html_files2 = join " ", map { "/var/www/ssl/chronos/$_" } @html_files;
    
    my $return = <<EOF;
lang_install:
	mkdir -p /usr/share/chronos/lang
	install -m 644 $langfiles /usr/share/chronos/lang

html_install:
	mkdir -p /var/www/ssl/chronos
	install -m 644 $html_files /var/www/ssl/chronos

startup_install:
	install -m 755 remindd /etc/rc.d/init.d

lang_uninstall:
EOF
    $return .= "\trm -f " . (join " ", map { "/usr/share/chronos/$_" } grep { -f } <lang/*>) . "\n";
    $return .= <<EOF;

html_uninstall:
	rm -f $html_files2

startup_uninstall:
	rm -f /etc/rc.d/init.d/remindd
EOF
    return $return;
}
