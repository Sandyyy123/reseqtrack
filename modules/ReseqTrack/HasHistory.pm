
=pod

=head1 NAME

ReseqTrack::HasHistory

=head1 SYNOPSIS

Base Class for objects which can have history or attribute objects attached to them

=head1 Example

my $file = ReseqTrack::File->new(
      -name => $path,
      -type => $type,
      -size => $size,
      -host => $host,
      -history => \@histories,
        );


=cut

package ReseqTrack::HasHistory;

use strict;
use warnings;
use vars qw(@ISA);

use ReseqTrack::Tools::Exception qw(throw warning);
use ReseqTrack::Tools::Argument qw(rearrange);

use ReseqTrack::Base;

@ISA = qw(ReseqTrack::Base);

=head2 new

  Arg [1]   : ReseqTrack::HasHistory
  Arg [2]   : arrayref of ReseqTrack::History objects
  Arg [3]   : arrayref of ReseqTrack::Attribute objects
  Function  : create ReseqTrack::HasHistory object
  Returntype: ReseqTrack::HasHistory
  Exceptions: 
  Example   : 

=cut

sub new {
    my ( $class, @args ) = @_;
    my $self = $class->SUPER::new(@args);
    my ( $history, $attributes ) =
      rearrange( [ 'HISTORY', 'ATTRIBUTES' ], @args );
    $self->history($history) if $history;
    $self->attributes($attributes) if $attributes;
    return $self;
}

=head2 history

  Arg [1]   : ReseqTrack::HasHistory
  Arg [2]   : ReseqTrack::History or array ref of ReseqTrack::History
  Function  : add history objects to internal arrayref. If no history objects
  are defined but a dbID and adaptor is the method will try and fetch any history 
  objects
  Returntype: arrayref of ReseqTrack::History
  Exceptions: throw if not passed a ReseqTrack::History object or arrayref of said
  objects
  Example   : 

=cut

sub history {
    my ( $self, $arg ) = @_;
    if ($arg) {
        $self->populate_history;
        if ( ref($arg) eq 'ARRAY' ) {
	  throw(
"Must pass ReseqTrack::HasHistory::history an arrayref of history objects"
	       ) if ( $arg->[0] && ( !$arg->[0]->isa("ReseqTrack::History") ) );
	  unless ( $arg->[0] ) {
	    throw( $arg . " appears to contain an undefined entry" );
	  }    $self->{history} = $self->uniquify_histories( $self->{history} );
	  push( @{ $self->{history} }, @$arg );
        }
        elsif ( $arg->isa("ReseqTrack::History") ) {
	  push( @{ $self->{history} }, $arg );
        }
        else {
	  throw(
		"Must give ReqseqTrack::File::history either a ReseqTrack::History "
		. "object or an arrayref of History objects not "
		. $arg );
        }
    }
    elsif ( !$self->{history} || @{ $self->{history} } == 0 ) {
        $self->populate_history;
    }

    return $self->{history};
}


sub fast_add_history{
  my ($self, $arg) = @_;
  if($arg){
    throw("Can't fast add an array must be ReseqTrack::History not ".
	  $arg) unless($arg->isa("ReseqTrack::History"));
    push(@{$self->{history}}, $arg);
    $self->{history} = $self->uniquify_histories($self->{history});
  }
  return $self->{history};
}

=head2 populate_history

  Arg [1]   : ReseqTrack::HasHistory
  Function  : gets history objects from the database and ensures they are all unique
  Returntype: n/a
  Exceptions: warns if non unique history objects are found
  Example   : 

=cut

sub populate_history {
    my ($self) = @_;
    my @histories;
    if ( $self->adaptor && $self->dbID ) {
        my $hist_a = $self->adaptor->db->get_HistoryAdaptor;
        my $objects =
          $hist_a->fetch_by_other_id_and_table_name( $self->dbID,
            $self->object_table_name );
        push( @histories, @$objects ) if ( $objects && @$objects >= 1 );
    }
    push( @histories, @{ $self->{history} } ) if ( $self->{history} );
    $self->{history} = $self->uniquify_histories( \@histories );
}

=head2 uniquify_histories

  Arg [1]   : ReseqTrack::HasHistory
  Arg [2]   : arrayref of ReseqTrack::History objects
  Function  : produce a unique set of history objects based on timestamp and comment
  Returntype: arrayref of ReseqTrack::History objects
  Exceptions: 
  Example   : 

=cut

sub uniquify_histories {
    my ( $self, $histories ) = @_;
    my %hash;
  HISTORY: foreach my $history (@$histories) {
        my $comment = $history->comment;
        my $time    = $history->time;
        $time = '' if ( !$time );
        my $unique_string = $comment . "-" . $time;
        if ( $hash{$unique_string} ) {

            #warning($unique_string." is already defined skipping");
            next HISTORY;
        }
        $hash{$unique_string} = $history;
    }
    my @values = values(%hash);
    return \@values;
}

=head2 refresh_history

  Arg [1]   : ReseqTrack::HasHistory
  Function  : This will overwrite the existing history array and pull a new one
  from the database
  Returntype: arrayref of ReseqTrack::History
  Exceptions: warns if array current contains objects
  Example   : 

=cut

sub refresh_history {
    my ($self) = @_;
    if ( $self->adaptor && $self->dbID ) {
        my $hist_a = $self->adaptor->get_HistoryAdaptor;
        my $objects =
          $hist_a->fetch_by_object_id_and_table_name( $self->dbID,
            $self->object_table_name );
        if ( @{ $self->{history} } ) {
            warning(
                $self . "->{history} contains objects you will lose them now" );
        }
        $self->{history} = $objects;
    }
    return $self->{history};
}

sub empty_history {
  my ($self) = @_;
  $self->{history} = [];
}


=head2 attributes

  Arg [1]   : ReseqTrack::HasHistory
  Arg [2]   : arrayref of ReseqTrack::Attributes objects
  Function  : store arrayref of attribute objects, if no attributes objects are
  defined but a dbID and an adaptor it will try and fetch the attached attribute objects
  Returntype: arrayref of ReseqTrack::Attribute objects
  Exceptions: 
  Example   : 

=cut

sub attributes {
    my ( $self, $arg ) = @_;
    if ($arg) {
        $self->populate_attributes(1)
          ;    # $now has two stats objects, read and base
        if ( ref($arg) eq 'ARRAY' ) {
            if ( @$arg >= 1 ) {
                throw(
"Must pass ReseqTrack::HasHistory::attributes an arrayref of attributes objects"
                ) unless ( $arg->[0]->isa("ReseqTrack::Attribute") );
                push( @{ $self->{attributes} }, @$arg );
            }
        }
        elsif ( $arg->isa("ReseqTrack::Attribute") ) {
            push( @{ $self->{attributes} }, $arg );
        }
        else {
            throw(
"Must give ReqseqTrack::HasHistory::attributes either a ReseqTrack::Attribute "
                  . "object or an arrayref of attribute objects not "
                  . $arg );
        }
        $self->{attributes} = $self->uniquify_attributes( $self->{attributes} );
    }
    elsif ( !$self->{attributes} || @{ $self->{attributes} } == 0 ) {
        $self->populate_attributes;
    }
    return $self->{attributes};
}

=head2 populate_attributes

  Arg [1]   : ReseqTrack::HasHistory 
  Arg [2]   : 0/1 binary, if set to one the uniqufy attributes method isn't called
  Function  : populate the attributes array based on the dbID and the table name
  Returntype: n/a
  Exceptions: 
  Example   : 

=cut

sub populate_attributes {
    my ( $self, $dont_unique ) = @_;
    my @attributes;
    if ( $self->adaptor && $self->dbID ) {
        my $hist_a = $self->adaptor->db->get_AttributeAdaptor;
        my $objects =
          $hist_a->fetch_by_other_id_and_table_name( $self->dbID,
            $self->object_table_name );
        push( @attributes, @$objects ) if ( $objects && @$objects >= 1 );
    }
    push( @attributes, @{ $self->{attributes} } ) if ( $self->{attributes} );
    unless ($dont_unique) {
        $self->{attributes} = $self->uniquify_attributes( \@attributes );
    }
    else {
        $self->{attributes} = \@attributes;
    }
}

=head2 refresh_attributes

  Arg [1]   : ReseqTrack::HasHistory
  Function  : fetch a fresh set of attribute objects from the database and remove any already 
  attached attributes
  Returntype: arrayref of ReseqTrack::Attribute objects
  Exceptions: 
  Example   : 

=cut

sub refresh_attributes {
    my ($self) = @_;
    if ( $self->adaptor && $self->dbID ) {
        my $hist_a = $self->adaptor->get_AttributeAdaptor;
        my $objects =
          $hist_a->fetch_by_object_id_and_table_name( $self->dbID,
            $self->object_table_name );
        if ( @{ $self->{attributes} } ) {
            warning( $self
                  . "->{attributes} contains objects you will lose them now" );
        }
        $self->{attributes} = $objects;
    }
    return $self->{attributes};
}

=head2 uniquify_attributes

  Arg [1]   : ReseqTrack::HasHistory
  Arg [2]   : arrayref of ReseqTrack::Attribute objects
  Function  : produce a unique set of attributes objects based on timestamp and comment
  Returntype: arrayref of ReseqTrack::Attribute objects
  Exceptions: 
  Example   : 

=cut

sub uniquify_attributes {
    my ( $self, $attributes ) = @_;
    my %hash;
    my %id;   #key is obj att name, value is its dbID
              # This function takes an array of stats objects for the same file,
     # merge stats with the same attribute name and update the  attribute value.
     # some stats objects have not been loaded in db so they do not have dbID, in these cases, dbID would be inherited from existing tats object
  HISTORY: foreach my $stats (@$attributes) {
        if ( $hash{ $stats->attribute_name } ) {
            if ( $stats->dbID ) {
                $id{ $stats->attribute_name } = $stats->dbID;
            }
            else {
                $stats->dbID( $id{ $stats->attribute_name } );
            }
            $hash{ $stats->attribute_name } = $stats
              ;   #this way the same attribute name always gets the latest value
             #warning($stats->attribute_name." is already defined, the attribute value is overwritten with the new value");
            next HISTORY;
        }
        else {
            $hash{ $stats->attribute_name } = $stats;
            $id{ $stats->attribute_name }   = $stats->dbID;
        }
    }
    my @values = values(%hash);

    return \@values;
}

=head2 replace_attributes

  Arg [1]   : ReseqTrack::HasHistory
  Arg [2]   : ReseqTrack::Attribute
  Function  : replace one attribute object of the same attribute name with another
  Returntype: arrayref of attribute objects
  Exceptions: 
  Example   : 

=cut

sub replace_attributes {
    my ( $self, $attribute ) = @_;
    my %hash;
    foreach my $attributes ( @{ $self->attributes } ) {
        $hash{ $attributes->attribute_name } = $attributes
          ;    #this way the same attribute name always gets the latest value
    }

    $hash{ $attribute->attribute_name } = $attribute;
    my @values = values(%hash);
    return \@values;
}

sub attributes_hash {
  my ($self) = @_;
  
  my %attrs;
  for my $a (@{$self->attributes()}){
    $attrs{$a->attribute_name} = $a;
  }
  return \%attrs;
}

1;
