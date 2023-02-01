package Mojo::IOLoop::Thread;
use Mojo::Base 'Mojo::IOLoop::Subprocess';

our $VERSION = "0.10";

use threads;
use Thread::Queue;

use Mojo::IOLoop;
use Mojo::Util qw(dumper monkey_patch);

BEGIN {
    ## no critic ( PrivateSubs )
    monkey_patch 'Mojo::IOLoop', subprocess => sub {
        my $self = shift;
        my $instance = ref($self) ? $self : $self->singleton;
        my $mit = Mojo::IOLoop::Thread->new(ioloop => $instance);
        return @_ ? $mit->run(@_) : $mit;
    }
}

sub pid  { threads->tid() || shift->{pid}  };

sub _start {
  my ($self, $child, $parent) = @_;

  $self->{queue} = Thread::Queue->new();
  my $tid = $self->{pid} = $self->_thread($child);
  $self->emit('spawn');
  
  my $id;
  $id = $self->ioloop->recurring(0.05 => sub {
	my $ioloop = shift;
    while ( my $args = $self->{queue}->dequeue_nb() ) {
      $self->emit(progress => @$args);
    }
	
	return $ioloop->remove($id) unless my $thread = threads->object($tid);
	
    if ($thread->is_joinable() && !$thread->is_running && !$thread->is_detached) {
	  $ioloop->remove($id);
	  my $results = eval { $self->deserialize->($thread->join) } // [];
	  my $err = shift(@$results) // $@;
      $self->{exit_code} = $err ? 1 : 0;
	  $self->$parent($err, @$results);
    } else {
      threads->yield();
    }
  });

  return $self;
}

sub _thread {
  my $self   = shift;
  my $child  = shift;
  my $thread = threads->create(
    {exit => 'thread_only', scalar => 1},
    sub {
      my ($self) = @_;
      $self->ioloop->reset({freeze => !!(threads->tid)});
      my $results = eval { [$self->$child] } // [];
      $self->emit('cleanup');
	  return $self->serialize->([$@, @$results]);
    },
	$self
  );
  return $thread->tid();
}

sub progress {
  my ($self, @args) = @_;
  $self->{queue}->enqueue(\@args);
}

1;

__END__

=encoding utf-8

=head1 NAME

Mojo::IOLoop::Thread - Threaded Replacement for Mojo::IOLoop::Subprocess

=head1 SYNOPSIS

  use Mojo::IOLoop::Thread;

  # Operation that would block the event loop for 5 seconds
  my $subprocess = Mojo::IOLoop::Thread->new;
  $subprocess->run(
    sub {
      my $subprocess = shift;
      sleep 5;
      return '♥', 'Mojolicious';
    },
    sub {
      my ($subprocess, $err, @results) = @_;
      say "Subprocess error: $err" and return if $err;
      say "I $results[0] $results[1]!";
    }
  );

  # Start event loop if necessary
  $subprocess->ioloop->start unless $subprocess->ioloop->is_running;

or

  use Mojo::IOLoop;
  use Mojo::IOLoop::Thread;

  my $iol = Mojo::IOLoop->new;
  $iol->subprocess(
    sub {'♥'},
    sub {
      my ($subprocess, $err, @results) = @_;
      say "Subprocess error: $err" and return if $err;
      say @results;
    }
  );
  $loop->start;

=head1 DESCRIPTION

L<Mojo::IOLoop::Thread> is a multithreaded alternative for
L<Mojo::IOLoop::Subprocess> which is not available under Win32.
It is a dropin replacement, takes the same parameters and works
analoguous by just using threads instead of forked processes.

L<Mojo::IOLoop::Thread> replaces L<Mojo::IOLoop/subprocess> with a threaded
version on module load.

=head1 BUGS and LIMITATIONS

C<exit_code> will not work like L<Mojo::IOLoop::Subprocess/exit_code> because threads
are not able to pass the exit code back when they are joined by the main thread.
Additionally the exit code will be set when the subprocess is run with C<run_p>
(see L<Mojo::IOLoop::Subprocess/run_p>)

=head1 AUTHOR

Thomas Kratz E<lt>tomk@cpan.orgE<gt>

=head1 REPOSITORY

L<https://github.com/tomk3003/mojo-ioloop-thread>

=head1 COPYRIGHT

Copyright 2017-21 Thomas Kratz.

=head1 LICENSE

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=cut
