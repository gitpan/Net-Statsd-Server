#
# Flush stats to graphite (http://graphite.wikidot.com/).
#
# To enable this backend, include 'graphite' in the backends
# configuration array:
#
#   backends: ['graphite']
#
# This backend supports the following config options:
#
#   graphiteHost: Hostname of graphite server.
#   graphitePort: Port to contact graphite server at.
#

package Net::Statsd::Server::Backend::Graphite;

use 5.010;
use strict;
use warnings;
use base qw(Net::Statsd::Server::Backend);

use AnyEvent::Log;
use IO::Socket::INET ();
use Time::HiRes      ();

use constant {
  fmt_FLOAT => '%.6f',
  fmt_INT   => '%d',
  fmt_STR   => '%s',
  fmt_TIME  => '%d',
};

sub init {
  my ($self, $startup_time, $config) = @_;

  for (qw(debug graphiteHost graphitePort)) {
    $self->{$_} = $config->{$_};
  }

  $config->{graphite} ||= {};

  my $globalPrefix    = $config->{graphite}->{globalPrefix}    // "stats";
  my $prefixCounter   = $config->{graphite}->{prefixCounter}   // "counters";
  my $prefixTimer     = $config->{graphite}->{prefixTimer}     // "timers";
  my $prefixGauge     = $config->{graphite}->{prefixGauge}     // "gauges";
  my $prefixSet       = $config->{graphite}->{prefixSet}       // "sets";
  my $legacyNamespace = $config->{graphite}->{legacyNamespace} // 1;

  my $globalNamespace  = [];
  my $counterNamespace = [];
  my $timerNamespace   = [];
  my $gaugesNamespace  = [];
  my $setsNamespace    = [];

  if ($legacyNamespace) {

    $globalNamespace  = ['stats'];
    $counterNamespace = ['stats'];
    $timerNamespace   = ['stats', 'timers'];
    $gaugesNamespace  = ['stats', 'gauges'];
    $setsNamespace    = ['stats', 'sets'];

  }
  else {

    if ($globalPrefix ne "") {
      push @{ $globalNamespace },  $globalPrefix;
      push @{ $counterNamespace }, $globalPrefix;
      push @{ $timerNamespace },   $globalPrefix;
      push @{ $gaugesNamespace },  $globalPrefix;
      push @{ $setsNamespace },    $globalPrefix;
    }

    if ($prefixCounter ne "") {
      push @{ $counterNamespace }, $prefixCounter;
    }

    if ($prefixTimer ne "") {
      push @{ $timerNamespace }, $prefixTimer;
    }

    if ($prefixGauge ne "") {
      push @{ $gaugesNamespace }, $prefixGauge;
    }

    if ($prefixSet ne "") {
      push @{ $setsNamespace }, $prefixSet;
    }

  }

  $self->{globalPrefix}     = $globalPrefix;
  $self->{prefixCounter}    = $prefixCounter;
  $self->{prefixTimer}      = $prefixTimer;
  $self->{prefixGauge}      = $prefixGauge;
  $self->{prefixSet}        = $prefixSet;
  $self->{legacyNamespace}  = $legacyNamespace;

  $self->{globalNamespace}  = $globalNamespace;
  $self->{counterNamespace} = $counterNamespace;
  $self->{timerNamespace}   = $timerNamespace;
  $self->{gaugesNamespace}  = $gaugesNamespace;
  $self->{setsNamespace}    = $setsNamespace;

  #$self->{graphiteStats}->{last_flush} =
  #$self->{graphiteStats}->{last_exception} = $startup_time;

  $self->{flushInterval} = $config->{flushInterval};
}

sub flush {
  my ($self, $timestamp, $metrics) = @_;
  my $flush_stats = $self->flush_stats($timestamp, $metrics);
  $self->post_stats($flush_stats);
}

sub flush_stats {
  my ($self, $ts, $metrics) = @_;

  my $startTime = [ Time::HiRes::gettimeofday ];
  my $statString = "";
  my $num_stats = 0;
  my $timer_data_key;

  my $counters = $metrics->{counters};
  my $gauges = $metrics->{gauges};
  my $timers = $metrics->{timers};
  my $sets = $metrics->{sets};
  my $counter_rates = $metrics->{counter_rates};
  my $timer_data = $metrics->{timer_data};
  my $statsd_metrics = $metrics->{statsd_metrics};

  # Accumulate flush statistics into a list
  my @fstats;

  for my $key (keys %{ $counters }) {

    my @namespace = (@{ $self->{counterNamespace} }, $key);
    my $namespace = join(".", @namespace);

    my $value = $counters->{$key};
    my $valuePerSecond = $counter_rates->{$key}; # pre-calculated "per second" rate

    if ($self->{legacyNamespace}) {
      push @fstats, stat_float($namespace, $valuePerSecond, $ts);
      push @fstats, stat_int("stats_counts.$key", $value, $ts);
    } else {
      push @fstats, stat_float("$namespace.rate", $valuePerSecond, $ts);
      push @fstats, stat_int("$namespace.count", $value, $ts);
    }

    $num_stats++;
  }

  for my $key (keys %{ $timer_data }) {
    if ($timer_data->{$key} && keys %{ $timer_data->{$key} } > 0) {
      for my $timer_data_key (keys %{ $timer_data->{$key} }) {
        my @namespace = (@{ $self->{timerNamespace} }, $key);
        my $the_key = join(".", @namespace);
        push @fstats, stat_float(
          "$the_key.$timer_data_key",
          $timer_data->{$key}->{$timer_data_key}, $ts
        );
      }
      $num_stats++;
    }
  }

  for my $key (keys %{ $gauges }) {
    my @namespace = (@{ $self->{gaugesNamespace} }, $key);
    push @fstats, stat_float(join(".", @namespace), $gauges->{$key}, $ts);
    $num_stats++;
  }

  for my $key (keys %{ $sets }) {
    my @namespace = (@{ $self->{setsNamespace} }, $key);
    my $set_count = join(".", @namespace, "count");
    my $set_len = scalar keys %{ $sets->{$key} };
    push @fstats, stat_int($set_count, $set_len, $ts);
    $num_stats++;
  }

  my @namespace = (@{ $self->{globalNamespace} }, "statsd");

  # Convert Time::HiRes format (µs) to ms
  my $calcTime = 1000 * Time::HiRes::tv_interval($startTime);

  if ($self->{legacyNamespace}) {
    push @fstats, stat_int("statsd.numStats", $num_stats, $ts);
    push @fstats, stat_float("stats.statsd.graphiteStats.calculationtime",
      $calcTime, $ts);
    for my $key (keys %{ $statsd_metrics }) {
      push @fstats, stat_int("stats.statsd.$key", $statsd_metrics->{$key}, $ts);
    }
  }
  else {
    my $namespace = join(".", @namespace);
    push @fstats, stat_int("${namespace}.numStats", $num_stats, $ts);
    push @fstats, stat_float(
      "${namespace}.graphiteStats.calculationtime", $calcTime, $ts);
    for my $key (keys %{ $statsd_metrics }) {
      my $value = $statsd_metrics->{$key};
      push @fstats, stat_str("${namespace}.${key}", $value, $ts);
    }
  }

  my $global_stats = $self->global_stats();
  push @fstats, @{ $global_stats };

  return \@fstats;
}

sub global_stats {
  my ($self) = @_;

  my $last_flush = $self->{lastFlush} || 0;
  my $last_exception = $self->{lastException} || 0;
  my $ts = time();

  my @namespace = (@{ $self->{globalNamespace} }, 'statsd', 'graphiteStats');
  my $namespace = join(".", @namespace);

  my $global_stats = [
    stat_time("${namespace}.last_exception", $last_exception, $ts),
    stat_time("${namespace}.last_flush", $last_flush, $ts),
  ];

  return $global_stats;
}

sub post_stats {
  my ($self, $stat_list) = @_;

  return if ! $self->{graphiteHost};

  eval {
    my $host = $self->{graphiteHost};
    my $port = $self->{graphitePort};
    my $graphite = IO::Socket::INET->new(
      PeerHost => $host,
      PeerPort => $port,
    ) or die "Can't connect to Graphite on ${host}:${port}: $!";

    my $stat_string = $self->stats_to_string($stat_list);
    $graphite->send($stat_string);
    $graphite->close();

    $self->{lastFlush} = [Time::HiRes::gettimeofday];
  }
  or do {
    if ($self->{debug}) {
      # TODO use logger!
      warn("Exception while posting stats to Graphite: $@");
    }
    $self->{lastException} = [Time::HiRes::gettimeofday];
  };

}

sub stat_float {
  my ($stat, $val, $ts) = @_;
  return {
    stat  => $stat,
    value => $val,
    time  => $ts,
    fmt   => fmt_FLOAT,
  };
}

sub stat_int {
  my ($stat, $val, $ts) = @_;
  return {
    stat  => $stat,
    value => $val,
    time  => $ts,
    fmt   => fmt_INT,
  };
}

sub stat_str {
  my ($stat, $val, $ts) = @_;
  return {
    stat  => $stat,
    value => $val,
    time  => $ts,
    fmt   => fmt_STR,
  };
}

sub stat_time {
  my ($stat, $val, $ts) = @_;
  return {
    stat  => $stat,
    value => $val,
    time  => $ts,
    fmt   => fmt_TIME,
  };
}

sub stats_to_string {
  my ($self, $stat_list) = @_;
  my $stat_string = "";
  for (@{ $stat_list }) {
    my $attr = $_;
    my $stat = $attr->{stat};
    my $val  = $attr->{value};
    my $ts   = $attr->{time};
    my $fmt  = exists $attr->{fmt} ? $attr->{fmt} : '%d';
    $stat_string .= sprintf("%s $fmt %d\n", $stat, $val, $ts);
  }
  return $stat_string;
}

sub status {
  my ($self) = @_;
  return {
    last_flush     => $self->since($self->{lastFlush}),
    last_exception => $self->since($self->{lastException}),
  };
}

1;
