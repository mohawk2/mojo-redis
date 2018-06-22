use Mojo::Base -strict;
use Test::More;
use Mojo::Util 'trim';
use Mojo::Redis::Database;
use Mojo::Redis::PubSub;
use Mojo::UserAgent;

plan skip_all => 'CHECK_METHOD_COVERAGE=1' unless $ENV{CHECK_METHOD_COVERAGE};

my $methods = Mojo::UserAgent->new->get('https://redis.io/commands')->res->dom->find('[data-name]');
my @classes = qw(Mojo::Redis::Database Mojo::Redis::PubSub);
my (%doc, %skip);

$skip{$_} = 1 for qw(auth quit select);              # methods
$skip{$_} = 1 for qw(cluster hyperloglog server);    # groups

$methods = $methods->map(sub {
  $doc{$_->{'data-name'}} = [
    trim($_->at('.summary')->text),
    join(', ', map { $_ = trim($_); /^\w/ ? "\$$_" : $_ } grep {/\w/} split /[\n\r]+/, $_->at('.args')->text)
  ];
  return [$_->{'data-group'}, $_->{'data-name'}];
});

METHOD:
for my $t (sort { "@$a" cmp "@$b" } @$methods) {
  my $method = $t->[1];
  $method =~ s!\s!_!g;

  # Translate and/or skip methods
  $method = 'listen'   if $method =~ /subscribe$/;
  $method = 'unlisten' if $method =~ /unsubscribe$/;

  if ($skip{$t->[0]}++) {
    local $TODO = sprintf 'Add Mojo::Redis::%s', ucfirst $t->[1];
    ok 0, "not implemented: $method (@$t)";
    next METHOD;
  }
  if ($skip{$t->[1]} or $method eq 'pubsub') {
    note "Skipping @$t";
    next METHOD;
  }

REDIS_CLASS:
  for my $class (@classes) {
    next REDIS_CLASS unless $class->can($method);
    ok 1, "$class can $method (@$t)";
    next METHOD;
  }
  ok 0, "not implemented: $method (@$t)";
}

if (open my $SRC, '<', $INC{'Redis/Database.pm'}) {
  my (@source, %has_doc);

  while (<$SRC>) {
    $has_doc{$_} = 1 if /^=head2 (\w+)/;
    push @source, $_;
  }

  for my $method (sort @Mojo::Redis::Database::BASIC_OPERATIONS) {
    next if $has_doc{$method} or !$doc{$method};
    my ($summary, $args) = @{$doc{$method}};
    $summary .= '.' unless $summary =~ /\W$/;

    print <<"HERE";

=head2 $method

  \@res     = \$self->$method($args);
  \$self    = \$self->$method($args, sub { my (\$self, \@res) = \@_ });
  \$promise = \$self->${method}_p($args);

$summary

See L<https://redis.io/commands/$method> for more information.
HERE
  }
}

done_testing;