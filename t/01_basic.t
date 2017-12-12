use Mojo::Base -strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;

BEGIN {
    BAIL_OUT("OS unsupported\n")
        unless $^O eq "MSWin32" || $^O eq "cygwin";
    $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll'
}

use Mojo::IOLoop;
use Mojo::IOLoop::Thread;

# Huge result
my ($fail, $result);
my $subprocess = Mojo::IOLoop::Thread->new;
$subprocess->run(
  sub { shift->pid . $$ . ('x' x 100000) },
  sub {
    my ($subprocess, $err, $two) = @_;
    $fail = $err;
    $result .= $two;
  }
);
Mojo::IOLoop->start;
ok !$fail, 'no error';
is $result, $$  . $subprocess->pid . ('x' x 100000), 'right result';

# Custom event loop
($fail, $result) = ();
my $loop = Mojo::IOLoop->new;
$loop->subprocess(
  sub {'♥'},
  sub {
    my ($subprocess, $err, @results) = @_;
    $fail   = $err;
    $result = \@results;
  }
);
$loop->start;
ok !$fail, 'no error';
is_deeply $result, ['♥'], 'right structure';

# Multiple return values
($fail, $result) = ();
$subprocess = Mojo::IOLoop::Thread->new;
$subprocess->run(
  sub { return '♥', [{two => 2}], 3 },
  sub {
    my ($subprocess, $err, @results) = @_;
    $fail   = $err;
    $result = \@results;
  }
);
Mojo::IOLoop->start;
ok !$fail, 'no error';
is_deeply $result, ['♥', [{two => 2}], 3], 'right structure';
# Event loop in subprocess
($fail, $result) = ();
$subprocess = Mojo::IOLoop::Thread->new;
$subprocess->run(
  sub {
    my $result;
    Mojo::IOLoop->next_tick(sub { $result = 23 });
    Mojo::IOLoop->start;
    return $result;
  },
  sub {
    my ($subprocess, $err, $twenty_three) = @_;
    $fail   = $err;
    $result = $twenty_three;
  }
);
Mojo::IOLoop->start;
ok !$fail, 'no error';
is $result, 23, 'right result';

# Concurrent subprocesses
($fail, $result) = ();
Mojo::IOLoop->delay(
  sub {
    my $delay = shift;
    Mojo::IOLoop->subprocess(sub {1}, $delay->begin);
    Mojo::IOLoop->subprocess(sub {2}, $delay->begin);
  },
  sub {
    my ($delay, $err1, $result1, $err2, $result2) = @_;
    $fail = $err1 || $err2;
    $result = [$result1, $result2];
  }
)->wait;
ok !$fail, 'no error';
is_deeply $result, [1, 2], 'right structure';

# No result
($fail, $result) = ();
Mojo::IOLoop::Thread->new->run(
  sub {return},
  sub {
    my ($subprocess, $err, @results) = @_;
    $fail   = $err;
    $result = \@results;
  }
);
Mojo::IOLoop->start;
ok !$fail, 'no error';
is_deeply $result, [], 'right structure';

# Stream inherited from previous subprocesses
($fail, $result) = ();
my $delay = Mojo::IOLoop->delay;
my $me    = threads->tid();
for (0 .. 1) {
  my $end        = $delay->begin;
  my $subprocess = Mojo::IOLoop::Thread->new;
  $subprocess->run(
    sub { 1 + 1 },
    sub {
      my ($subprocess, $err, $two) = @_;
      $fail ||= $err;
      push @$result, $two;
      is $me, threads->tid(), 'we are the parent';
      $end->();
    }
  );
}
$delay->wait;
ok !$fail, 'no error';
is_deeply $result, [2, 2], 'right structure';

# Exception
$fail = undef;
Mojo::IOLoop::Thread->new->run(
  sub { die 'Whatever' },
  sub {
    my ($subprocess, $err) = @_;
    $fail = $err;
  }
);
Mojo::IOLoop->start;
like $fail, qr/Whatever/, 'right error';

# Serialization error
$fail       = undef;
$subprocess = Mojo::IOLoop::Thread->new;
$subprocess->run(
  sub { die 'Whatever' },
  sub {
    my ($subprocess, $err) = @_;
    $fail = $err;
  }
);
Mojo::IOLoop->start;
like $fail, qr/Whatever/, 'right error';

done_testing();

