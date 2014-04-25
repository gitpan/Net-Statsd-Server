
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "a Perl port of Etsy's statsd *server*",
  "AUTHOR" => "Cosimo Streppone <cosimo\@cpan.org>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Net-Statsd-Server",
  "EXE_FILES" => [
    "bin/exampleConfig.js",
    "bin/statsd",
    "bin/localConfig.js"
  ],
  "LICENSE" => "perl",
  "NAME" => "Net::Statsd::Server",
  "PREREQ_PM" => {
    "AnyEvent::Handle::UDP" => 0,
    "IO::Socket::INET" => 0,
    "JSON::XS" => 0
  },
  "TEST_REQUIRES" => {
    "Test::More" => 0
  },
  "VERSION" => "0.14",
  "test" => {
    "TESTS" => "t/*.t t/integration-tests/*.t"
  }
);


my %FallbackPrereqs = (
  "AnyEvent::Handle::UDP" => 0,
  "IO::Socket::INET" => 0,
  "JSON::XS" => 0,
  "Test::More" => 0
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



