
use lib "lib";
use Module::Build;

use File::Spec;

my $build = Module::Build->new (
    dist_name         => "WWW-MechanizeExt",
    dist_version      => "0.50",
    dist_author       => "spadkins\@gmail.com",
    dist_abstract     => "extends WWW::Mechanize to add debugging and diagnostic features",
    license           => "perl",
    requires => {
        # "App::Options"    => 0,    # configuration
        "WWW::Mechanize"    => 0.01, # web crawling (user-agent/browser emulation)
        "HTML::TokeParser"  => 0.01, # parses HTML pages
    },
    build_requires => {
        "Module::Build"   => 0,  # needed for installing the software
    },
);

$build->create_build_script;

