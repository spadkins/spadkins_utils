
use Module::Build;

use File::Spec;

my $build = Module::Build->new (
    dist_name         => "WWW-Selenium-Simple",
    dist_version      => "0.50",
    dist_author       => "spadkins\@gmail.com",
    dist_abstract     => "Run Selenium test scripts (captured by the Firefox Selenium IDE) using WWW::Mechanize (without the need of a Selenium Remote Control Server)",
    license           => "perl",
    requires => {
        "App::Options"      => 0.01, # configuration
        "URI"               => 0.01, # parsing and constructing URI's and URL's
        "WWW::Mechanize"    => 0.01, # web crawling (user-agent/browser emulation)
        "HTML::TokeParser"  => 0.01, # parses HTML pages
    },
    build_requires => {
        "Module::Build"     => 0.01, # needed for installing the software
    },
);

$build->create_build_script;

