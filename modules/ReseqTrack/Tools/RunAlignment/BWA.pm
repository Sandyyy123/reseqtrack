package ReseqTrack::Tools::RunAlignment::BWA;

use strict;
use warnings;
use vars qw(@ISA);

use ReseqTrack::Tools::Exception qw(throw warning);
use ReseqTrack::Tools::Argument qw(rearrange);
use ReseqTrack::Tools::RunAlignment;

@ISA = qw(ReseqTrack::Tools::RunAlignment);

=pod

=head1 NAME

ReseqTrack::Tools::RunAlignment::BWA

=head1 SYNOPSIS

class for running BWA. Child class of ReseqTrack::Tools::RunAlignment

=head1 Example

my $bwa = ReseqTrack::Tools::RunAlignment::BWA(
                      -input => '/path/to/file'
                      -reference => '/path/to/reference',
                      -options => {'threads' => 4},
                      -paired_length => 3000,
                      -read_group_fields => {'ID' => 1, 'LB' => 'my_lib'},
                      -first_read => 1000,
                      -last_read => 2000,
                      );
$bwa->run;
my $output_file_list = $bwa->output_files;

=cut

sub DEFAULT_OPTIONS { return {
        'read_trimming' => 15,
        'mismatch_penalty' => undef,
        'gap_open_penalty' => undef,
        'gap_extension_penalty' => undef,
        'max_gap_opens' => undef,
        'max_gap_extensions' => undef,
        'threads' => 1,
        'load_fm_index' => 1,
        'disable_smith_waterman' => 0,
        };
}

sub new {
	my ( $class, @args ) = @_;
	my $self = $class->SUPER::new(@args);

	#setting defaults
        if (!$self->program) {
          if ($ENV{BWA}) {
            $self->program($ENV{BWA} . '/bwa');
          }
          else {
            $self->program('bwa');
          }
        }

	return $self;
}

sub run_alignment {
    my ($self) = @_;
    
    if ( $self->fragment_file ) {
        $self->run_samse_alignment();
    }
    
    if ( $self->mate1_file && $self->mate2_file ) {
        $self->run_sampe_alignment();
    }

    return;
}

sub run_sampe_alignment {
    my ($self) = @_;
    my $mate1_sai =
      $self->run_aln_mode( "mate1" );
    my $mate2_sai =
      $self->run_aln_mode( "mate2" );
    my $output_file = $self->working_dir() . '/'
        . $self->job_name . '_pe';
    $output_file .= ($self->output_format eq 'BAM' ? '.bam' : '.sam');
    $output_file =~ s{//}{/};

    my @cmd_words;
    push(@cmd_words, $self->program, 'sampe');
    push(@cmd_words, '-P') if $self->options('load_fm_index');
    push(@cmd_words, '-s') if $self->options('disable_smith_waterman');
    if ($self->paired_length) {
      my $max_insert_size = 3 * $self->paired_length;
      push(@cmd_words, '-a', $max_insert_size);
    }

    if ($self->read_group_fields->{'ID'}) {
      my $rg_string = q("@RG\tID:) . $self->read_group_fields->{'ID'};
      RG:
      while (my ($tag, $value) = each %{$self->read_group_fields}) {
        next RG if ($tag eq 'ID');
        next RG if (!$value);
        $rg_string .= '\t' . $tag . ':' . $value;
      }
      $rg_string .= q(");
      push(@cmd_words, '-r', $rg_string);
    }
    push(@cmd_words, $self->reference, $mate1_sai, $mate2_sai);
    push(@cmd_words, $self->get_fastq_cmd_string('mate1'));
    push(@cmd_words, $self->get_fastq_cmd_string('mate2'));
    if ($self->output_format eq 'BAM') {
      push(@cmd_words, '|', $self->samtools, 'view -bS -');
    }
    push(@cmd_words, '>', $output_file);

    my $sampe_cmd = join(' ', @cmd_words);

    $self->output_files($output_file);
    $self->execute_command_line($sampe_cmd);

    return $output_file;
}

sub run_samse_alignment {
    my ($self) = @_;

    my $sai_file =
      $self->run_aln_mode( "frag" );

    my $output_file = $self->working_dir() . '/'
        . $self->job_name . '_se';
    $output_file .= ($self->output_format eq 'BAM' ? '.bam' : '.sam');
    $output_file =~ s{//}{/};

    my @cmd_words;
    push(@cmd_words, $self->program, 'samse');

    if ($self->read_group_fields->{'ID'}) {
      my $rg_string = q("@RG\tID:) . $self->read_group_fields->{'ID'};
      RG:
      while (my ($tag, $value) = each %{$self->read_group_fields}) {
        next RG if ($tag eq 'ID');
        next RG if (!$value);
        $rg_string .= '\t' . $tag . ':' . $value;
      }
      $rg_string .= q(");
      push(@cmd_words, '-r', $rg_string);
    }
    push(@cmd_words, $self->reference, $sai_file);
    push(@cmd_words, $self->get_fastq_cmd_string('frag'));

    if ($self->output_format eq 'BAM') {
      push(@cmd_words, '|', $self->samtools, 'view -bS -');
    }
    push(@cmd_words, '>', $output_file);

    my $samse_cmd = join(' ', @cmd_words);
      
    $self->output_files($output_file);
    $self->execute_command_line($samse_cmd);

    return $output_file;
}

sub run_aln_mode {
    my ( $self, $fastq_type ) = @_;

    my $output_file = $self->working_dir . "/" . $self->job_name;
    $output_file .= ".$fastq_type.sai";

    my @cmd_words;
    push(@cmd_words, $self->program, 'aln');

    push(@cmd_words, '-q', $self->options('read_trimming'))
            if ($self->options('read_trimming'));
    push(@cmd_words, '-M', $self->options('mismatch_penalty'))
            if ($self->options('mismatch_penalty'));
    push(@cmd_words, '-O', $self->options('gap_open_penalty'))
            if ($self->options('gap_open_penalty'));
    push(@cmd_words, '-E', $self->options('gap_extension_penalty'))
            if ($self->options('gap_extension_penalty'));
    push(@cmd_words, '-o', $self->options('max_gap_opens'))
            if ($self->options('max_gap_opens'));
    push(@cmd_words, '-e', $self->options('max_gap_extensions'))
            if ($self->options('max_gap_extensions'));

    push(@cmd_words, '-t', $self->options('threads') || 1);
    push(@cmd_words, $self->reference);
    push(@cmd_words, $self->get_fastq_cmd_string($fastq_type));
    push(@cmd_words, '>', $output_file);

    my $aln_command = join(' ', @cmd_words);

    $self->created_files($output_file);
    $self->execute_command_line($aln_command);

    return $output_file;
}

1;

