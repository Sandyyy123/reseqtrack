package ReseqTrack::Hive::Process::RunBismark;

use strict;
use warnings;

use base ('ReseqTrack::Hive::Process::BaseProcess');
use ReseqTrack::Tools::FileSystemUtils qw(check_file_exists);
use ReseqTrack::Tools::RunBismark;
use ReseqTrack::Tools::Exception qw(throw);

sub param_defaults {
  return {
    program_file => undef,
    samtools => undef,
    options => {},
    add_attributes => 0,

    sample_source_id => undef,
    center_name => undef,
    library_name => undef,
    paired_nominal_length => undef,
    run_source_id => undef,
    instrument_platform => undef,
  };
}


sub run {
    my $self = shift @_;

    my $command = $self->param_required('command');

    my @allowed_cmds = qw(aln methext);
    throw("Don't recognise command $command. Acceptable commands are: @allowed_cmds")
	if (! grep {$command eq $_ } @allowed_cmds);

    if ($command eq 'aln') {
	my $base = $self->param_required('run_source_id');
	my $reference = $self->param_required('reference');
	my $multicore = $self->param_required('multicore');
	my $rgid = $self->param_required('rg_id');
	my $rgsample = $self->param_required('rg_sample');

	my $fastqs = $self->param_as_array('fastq');

	my $add_attributes = $self->param( 'add_attributes' ) ? 1 : 0;  

	foreach my $fastq (@$fastqs) {
	    check_file_exists($fastq);
	}
	my $run_alignment;
	if (scalar(@$fastqs)>1) {
	    my @sorted_fastqs=sort @$fastqs;
	    $run_alignment = ReseqTrack::Tools::RunBismark->new(
		-base => $base,
                -mate1_file => $sorted_fastqs[0],
		-mate2_file => $sorted_fastqs[1],
                -program => $self->param('program_file'),
		-multicore => $multicore,
                -samtools => $self->param('samtools'),
                -output_format => 'BAM',
		-rg_tag=>1,
		-rg_id=>$rgid,
		-rg_sample=>$rgsample,
                -working_dir => $self->output_dir,
                -reference => $reference,
                -job_name => $self->job_name,
                -options => $self->param('options'),
                );
	} else {
	    $run_alignment = ReseqTrack::Tools::RunBismark->new(
		-base => $base,
		-fragment_file => $fastqs->[0],
		-program => $self->param('program_file'),
		-multicore => $multicore,
		-samtools => $self->param('samtools'),
		-output_format => 'BAM',
		-rg_tag=>1,
                -rg_id=>$rgid,
                -rg_sample=>$rgsample,
		-working_dir => $self->output_dir,
		-reference => $reference,
		-job_name => $self->job_name,
		-options => $self->param('options'),
		);
	}

	$self->run_program($run_alignment,$command);

	if ($add_attributes) {
	    my $generated_metrics = $run_alignment->mapper_metrics_object;
	    throw('metrics object not found') unless $generated_metrics;
	    $self->output_param('attribute_metrics', $generated_metrics);
	}

	$self->output_param('bam', $self->output_dir."/".$run_alignment->bam_file);
	$self->output_param('mapper_report', $self->output_dir."/".$run_alignment->report_file);
    } elsif ($command eq 'methext') {
	my $fastqs = $self->param_as_array('fastq');
	my $runmode;
	if (scalar(@$fastqs)>1) {
	    $runmode='PAIRED';
	} else {
	    $runmode='SINGLE';
	}
	my $bamfile = $self->param_required('bam');
	my $multicore = $self->param_required('multicore');

	check_file_exists($bamfile);
	my $run_methext=ReseqTrack::Tools::RunBismark->new(
	    -input_files => $bamfile,
	    -working_dir => $self->output_dir,
	    -multicore => $multicore,
	    -runmode => $runmode,
	    -cutoff => $self->param('cutoff')
	    );
	$self->run_program($run_methext,$command);

	$self->output_param('mbias_txt', $run_methext->mbias_txt);
	$self->output_param('mbias_png', $run_methext->mbias_png);
	$self->output_param('bedgraph', $run_methext->bedgraph);
	$self->output_param('chh_context', $run_methext->chh_context);
	$self->output_param('cpg_context', $run_methext->cpg_context);
	$self->output_param('chg_context', $run_methext->chg_context);
	$self->output_param('splitting', $run_methext->splitting);
    }
}

1;

