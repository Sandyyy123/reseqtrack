package ReseqTrack::Tools::RunAlignment::Smalt;

use strict;
use warnings;

use ReseqTrack::Tools::Exception qw(throw warning);
use ReseqTrack::Tools::Argument qw(rearrange);
use File::Basename qw(fileparse);


use base qw(ReseqTrack::Tools::RunAlignment);

sub DEFAULT_OPTIONS { return {
        'threads' => 1,
        };
}

sub new {

    my ( $class, @args ) = @_;
    my $self = $class->SUPER::new(@args);

    my ( $index_prefix, $build_index_flag, $ref_index_file)
        = rearrange( [
            qw( INDEX_PREFIX BUILD_INDEX_FLAG REF_INDEX_FILE
                )], @args);


    $self->index_prefix($index_prefix);
    $self->build_index_flag($build_index_flag);
    $self->ref_index_file($ref_index_file);


    return $self;

}
#################################################################


sub run_alignment {
    my ($self) = @_;

    throw("need a ref_index file to output in the bam format")
      if($self->output_format eq 'BAM' && (! $self->ref_index_file));

    if ($self->build_index_flag){
        $self->build_index();
    }

    if ($self->fragment_file) {
        $self->run_se_alignment();
    }

    if ($self->mate1_file && $self->mate2_file) {
        $self->run_pe_alignment();
    }

    return;
}

sub run_se_alignment {
    my $self = shift;

    my $output_file = $self->working_dir() . '/'
        . $self->job_name . '_se';
    $output_file .= ($self->output_format eq 'BAM' ? '.bam' : '.sam');
    $output_file =~ s{//}{/};

    my $fastq = $self->fragment_file;
    my $fastq_cmd_string = ($self->first_read || $self->last_read) ? $self->get_fastq_cmd_string('frag')
          : ($fastq =~ /\.gz(?:ip)$/) ? "<(gunzip -c $fastq )"
          : $fastq;
		
		my @cmd_words;
    push(@cmd_words, $self->program, 'map');
    push(@cmd_words, '-n', $self->options('threads') || 1);
    push(@cmd_words, '-f', 'sam');
    push(@cmd_words, $self->index_prefix, $fastq_cmd_string);

    if ($self->output_format eq 'BAM') {
      push(@cmd_words, '|', $self->samtools, 'view -bS -');
      push(@cmd_words, '-t', $self->ref_index_file);
    }
    push(@cmd_words, '>', $output_file);

    my $cmd_line = join(' ', @cmd_words);

    $self->output_files($output_file);
    $self->execute_command_line($cmd_line);

    return $output_file ;
}

sub run_pe_alignment {
    my $self = shift;

    my $output_file = $self->working_dir() . '/'
        . $self->job_name . '_pe';
    $output_file .= ($self->output_format eq 'BAM' ? '.bam' : '.sam');
    $output_file =~ s{//}{/};

    my $fastq_mate1 = $self->mate1_file;
    my $fastq_mate2 = $self->mate2_file;

    my $fastq_cmd_string_mate1 = ($self->first_read || $self->last_read) ? $self->get_fastq_cmd_string('mate1')
          : ($fastq_mate1 =~ /\.gz(ip)?$/) ? "<(gunzip -c $fastq_mate1 )"
          : $fastq_mate1;
    my $fastq_cmd_string_mate2 = ($self->first_read || $self->last_read) ? $self->get_fastq_cmd_string('mate2')
          : ($fastq_mate2 =~ /\.gz(ip)?$/) ? "<(gunzip -c $fastq_mate2 )"
          : $fastq_mate2;

    my @cmd_words = ($self->program, 'map');
    push(@cmd_words, '-n', $self->options('threads') || 1);
    push(@cmd_words, '-f', 'sam');
    push(@cmd_words, $self->index_prefix, $fastq_cmd_string_mate1, $fastq_cmd_string_mate2);
    if ($self->output_format eq 'BAM') {
      push(@cmd_words, '|', $self->samtools, 'view -bS -');
      push(@cmd_words, '-t', $self->ref_index_file);
    }
    push(@cmd_words, '>', $output_file);

    my $cmd_line = join(' ', @cmd_words);

    $self->output_files($output_file);
    $self->execute_command_line($cmd_line);

    return $output_file ;
}

sub build_index {
    my $self = shift;

    my $index_prefix = $self->working_dir . '/'
                    . $self->job_name;
    $index_prefix =~ s{//}{/};

    my $reference = $self->reference;
    my $reference_cmd_string = ($reference =~ /\.gz(ip)?$/) ? "<(gunzip -c $reference)" : $reference;

    my $cmd_line = $self->program;
    $cmd_line .= ' index ' . $index_prefix . ' ' . $reference_cmd_string;

    $self->index_prefix($index_prefix);

    my $sma = $index_prefix . '.sma';
    my $smi = $index_prefix . '.smi';

    $self->created_files([$sma, $smi]);
    $self->execute_command_line($cmd_line);

    return;

}




sub index_prefix {
    my ( $self, $arg ) = @_;

    if ($arg) {
        $self->{index_prefix} = $arg;
    }
    return $self->{index_prefix};
}


sub build_index_flag {
    my ( $self, $arg ) = @_;

    if (defined $arg) {
        $self->{build_index_flag} = $arg;
    }
    return $self->{build_index_flag};
}

sub ref_index_file {
    my $self = shift;

    if (@_) {
        $self->{ref_index_file} = shift;
    }
    return $self->{ref_index_file};
}


1;

