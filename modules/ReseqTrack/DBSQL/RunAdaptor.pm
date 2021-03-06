package ReseqTrack::DBSQL::RunAdaptor;

use strict;
use warnings;
use base qw(ReseqTrack::DBSQL::LazyAdaptor);
use ReseqTrack::Run;

sub new {
  my ( $class, $db ) = @_;

  my $self = $class->SUPER::new($db);

  return $self;
}

sub column_mappings {
  my ( $self, $r ) = @_;

  throw("must be passed an object") unless ($r);

  return {
    run_id              => sub { $r->dbID(@_) },
    experiment_id       => sub { $r->experiment_id(@_) },
    run_alias           => sub { $r->run_alias(@_) },
    status              => sub { $r->status(@_) },
    md5                 => sub { $r->md5(@_) },
    center_name         => sub { $r->center_name(@_) },
    run_center_name     => sub { $r->run_center_name(@_) },
    instrument_platform => sub { $r->instrument_platform(@_) },
    instrument_model    => sub { $r->instrument_model(@_) },
    run_source_id       => sub { $r->run_source_id(@_) },
    submission_id       => sub { $r->submission_id(@_) },
    submission_date     => sub { $r->submission_date(@_) },
  };
}

sub object_class {
  return 'ReseqTrack::Run';
}

sub table_name {
  return "run";
}

sub fetch_by_source_id {
  my ( $self, $source_id ) = @_;
  return pop @{ $self->fetch_by_column_name( "run_source_id", $source_id ) };
}

sub fetch_by_experiment_id {
  my ( $self, $experiment_id ) = @_;
  return $self->fetch_by_column_name( "experiment_id", $experiment_id );
}

sub fetch_by_sample_id {
  my ( $self, $sample_id ) = @_;

  my $sql = join( ' ',
    'select distinct',
    $self->columns,
    'from',
    $self->table_name,
    ', run',
    'where',
    'experiment.sample_id = ?',
    'and experiment.experiment_id =',
    $self->table_name . '.experiment_id' );

  my @objects;
  my $sth = $self->prepare($sql);
  $sth->bind_param( 1, $sample_id );

  eval { $sth->execute; };
  if ($@) {
    throw("Problem running $sql $@");
  }
  while ( my $rowHashref = $sth->fetchrow_hashref ) {
    my $object = $self->object_from_hashref($rowHashref) if ($rowHashref);
    push( @objects, $object );
  }
  $sth->finish;
  return \@objects;
}

sub store {
  my ( $self, $run, $update ) = @_;
  my $existing_record = $self->fetch_by_dbID( $run->dbID ) if ( $run->dbID );

  if ( $existing_record && $update ) {
    $run->dbID( $existing_record->dbID );
    return $self->update($run);
  }

  if ( !$existing_record ) {
    $self->SUPER::store( $run, $update );
  }
}

1;
