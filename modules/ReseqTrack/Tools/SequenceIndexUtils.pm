package ReseqTrack::Tools::SequenceIndexUtils;

use strict;
#use warnings;
use Exporter;
use File::Copy;
use File::Basename;
use File::Find ();
use ReseqTrack::Tools::Exception;
use ReseqTrack::Tools::FileUtils;
use ReseqTrack::Tools::GeneralUtils;

use vars qw (@ISA  @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(
             get_index_hash
             find_file_size
             get_file_objects_from_index
             print_index_hash
             print_from_object
             return_header_string
		return_header_desc
             get_index_hash_on_column
             assign_files
             get_run_to_file_hash
             get_withdrawn_and_active_hash
	    );



sub get_withdrawn_and_active_hash{
  my ($file, $trim) = @_;
  open(FH, $file) or throw("IndexUtils:get_index_hash failed to open ".$file." $!");
  my $active_hash;
  my $withdrawn_hash;
  while(<FH>){
    next if(/SUBMISSION_ID/i);
    chomp;
    my @values = split /\t/, $_;
    my $name = $values[0];
    $name = basename($values[0]) if($trim);
    my $withdrawn = $values[20];
    my $withdrawn_status = $values[22];
    if($withdrawn){
      $withdrawn_hash->{$name} = $withdrawn_status;
    }else{
      $active_hash->{$name} = 1;
    }
  }
  return ($active_hash, $withdrawn_hash);
}

sub get_run_to_file_hash{
  my ($file, $trim) = @_;
  my $run_hash = get_index_hash_on_column($file, 2);
  my %run_to_file_hash;
  foreach my $run(keys(%$run_hash)){
    my $lines = $run_hash->{$run};
    my @files;
    foreach my $line(@$lines){
      my @values = split /\t/, $line;
      my $file = $values[0];
      my $name = $file;
      if($trim){
        $name = basename($file);
      }
      push(@files, $name);
    }
    my ($mate1, $mate2, $frag) = assign_files(\@files);
    $run_to_file_hash{$run} = {};
    $run_to_file_hash{$run}->{frag} = $frag;
    $run_to_file_hash{$run}->{mate1} = $mate1;
    $run_to_file_hash{$run}->{mate2} = $mate2;
  }
  return \%run_to_file_hash;
}

sub get_index_hash_on_column{
  my ($file, $column) = @_;
  $column = 0 if(!$column);
  my %hash;
  open(FH, $file) or throw("IndexUtils:get_index_hash failed to open ".$file." $!");
  while(<FH>){
    next if(/SUBMISSION_ID/i);
    chomp;
    my $line = $_;
    my @values = split /\t/, $line;
    my $key = $values[$column];
    $key = "undefined" unless(defined($key));
    $hash{$key} = [] if(!$hash{$key});
    push(@{$hash{$key}}, $line);
  }
  return \%hash;
}

sub get_index_hash{
  my ($file, $trim) = @_;
  my $line_count = 0;
  open(FH, $file) or throw("IndexUtils:get_index_hash failed to open ".$file." $!");
  my $hash;
  while(<FH>){
    next if(/SUBMISSION_ID/i);
    chomp;
    my @values = split /\t/, $_;
    my $name = $values[0];
    $name = basename($values[0]) if($trim);
    $name =~ s/\s+$//;
    $name =~ s/^\s+//;
    unless($hash->{$name}){
      $hash->{$name} = $_;
    }else{
      warning("Two lines in ".$file." has a first column entry of ".$name);
    }
  }
  close(FH);
  return $hash;
}

sub get_file_objects_from_index{
  my ($file, $db, $return_missing) = @_;
  open(FH, $file) or throw("IndexUtils:get_file_objects_from_index failed to open "
                           .$file." $!");
  my @files;
  my $fa = $db->get_FileAdaptor;
  my @missing_files;
  while(<FH>){
    next if(/SUBMISSION_ID/i);
    chomp;
    my @values = split /\t/, $_;
    my $name = $values[0];
    my ($filename, $dir) = fileparse($name);
    my $md5 = $values[1];
    my $files = $fa->fetch_by_name($filename);
    if(!$files || @$files == 0){
      unless($return_missing){
        throw("Can't find file for ".$name);
      }else{
        push(@missing_files, $name);
      }
    }
    my $file;
    if($files >= 2){
    FILE:foreach my $file_object(@$files){
      next unless($file_object->is_current);
      next if($md5 && $file_object->md5 ne $md5);
      next unless($file_object->full_path =~ /$dir/);
      $file = $file_object;
      last FILE if($file);
    }
    }else{
      $file = $files->[0];
    }
    if(!$file){
      warning("Failed to fetch a file for ".$values[0]);
      push(@missing_files, $values[0]);
    }else{
      push(@files, $file);
    }
  }
  close(FH);
  if($return_missing){
    return (\@files, \@missing_files);
  }else{
    return \@files;
  }
}

sub find_file_size{
  my ($file) = @_;
  open(FH, $file) or throw("IndexUtils:check_file_size failed to open ".
                            $file." $!");
  my %sanity_hash;
  while(<FH>){
    next if(/SUBMISSION_ID/i);
    chomp;
    my @values = split /\t/, $_;
    my $size = (-s $values[0]);
    $sanity_hash{$values[0]} = $size;
  }
  close(FH);
  return \%sanity_hash;
}


sub print_index_hash{
  my ($hash, $fh) = @_;
  $fh = \*STDOUT if(!$fh);
  foreach my $key(keys(%$hash)){
    my $string = $hash->{$key};
    print $fh $string."\n";
  }
}

sub return_header_desc {
	return join("\n", "##Date=",
		"##Project=The 1000 Genomes Project",
		"##FASTQ_ENA_PATH=an ENA ftp path from which the FASTQ file can be downloaded",
		"##MD5=md5 for the fastq file",
		"##RUN_ID=ENA/SRA assigned accession for the run",
		"##STUDY_ID=ENA/SRA assigned accession for the study",
		"##STUDY_NAME=name of the study",
		"##CENTER_NAME=sequencing center that produced and submitted the sequence data",
		"##SUBMISSION_ID=ENA/SRA assigned accession for the submission",
		"##SUBMISSION_DATE=date of the data was submitted to ENA/SRA",
		"##SAMPLE_ID=ENA/SRA assigned accession for the sample",
		"##SAMPLE_NAME=sample identifier given by Coriell",
		"##POPULATION=three letter population code for the sample",
		"##EXPERIMENT_ID=ENA/SRA assigned accession for the experiment",
		"##INSTRUMENT_PLATFORM=type of sequencing machine used in the experiment",
		"##INSTRUMENT_MODEL=model of the sequencing machine used in the experiment",
		"##LIBRARY_NAME=identifier for the library",
		"##RUN_NAME=run name assigned by the sequencing machine",
		"##RUN_BLOCK_NAME=run block name assigned by the machine",
		"##INSERT_SIZE=submitter specified insert size of the library",
		"##LIBRARY_LAYOUT=Library layout, this can be either PAIRED or SINGLE",
		"##PAIRED_FASTQ=Name of mate pair file if exists",
		"##WITHDRAWN=0/1 to indicate if the file has been withdrawn, only present if a file has been withdrawn",
		"##WITHDRAWN_DATE=this is generally the date the index file is generated on",
		"##COMMENT=comment about reasons for withdrawing from variant calling. \"TOO SHORT\" means reads are shorter than 70bp for WGS data or less than 68bp for WXS data; \"NOT_ILLUMINA\" are data produced on platformats other than Illumina; \"SUPPRESSED IN ARCHIVE\" are runs that are no longer available from ENA/SRA",
		"##READ_COUNT=number of reads in the fastq file",
		"##BASE_COUNT=number of bases in the fastq file",
		"##ANALYSIS_GROUP=the analysis group of the sequence, this reflects sequencing strategy. Currently this includes low coverage whole genome sequence (WGS), exome sequence (WXS), high coverage whole genome sequence (HC_WGS)"
	) . "\n";
}

sub return_header_string{
  return join("\t", '#FASTQ_ENA_PATH', 'MD5', 'RUN_ID', 'STUDY_ID', 'STUDY_NAME', 
              'CENTER_NAME', 'SUBMISSION_ID', 'SUBMISSION_DATE', 'SAMPLE_ID', 
              'SAMPLE_NAME', 'POPULATION', 'EXPERIMENT_ID', 'INSTRUMENT_PLATFORM', 
              'INSTRUMENT_MODEL', 'LIBRARY_NAME', 'RUN_NAME', 'RUN_BLOCK_NAME', 
              'INSERT_SIZE', 'LIBRARY_LAYOUT', 'PAIRED_FASTQ', 'WITHDRAWN', 
              'WITHDRAWN_DATE', 'COMMENT', 'READ_COUNT', 'BASE_COUNT', 
              'ANALYSIS_GROUP')."\n";
}

sub print_from_object{
  my ($file, $md5, $object, $paired_file, $withdrawn, $comment, $time, $read_count, 
      $run_count, $analysis_group, $fh) = @_;
  throw("Can't print a line if the file doesn't exist\n") if(!$file);
  no warnings;
  if($withdrawn){
    $time = current_time() if(!$time);
  }
  $analysis_group = 'low coverage' unless ($analysis_group);
  $withdrawn = 0 unless($withdrawn);
  $read_count = "not available" if(!$read_count);
  $run_count = "not available" if(!$run_count);
  $fh = \*STDOUT if(!$fh);
  print $file."\t";
  print $md5 ."\t";
  my @methods = ('run_id', 'study_id', 'study_name', 'center_name', 'submission_id', 
                 'submission_date', 'sample_id', 'sample_name', 'population', 
                 'experiment_id', 'instrument_platform', 'instrument_model', 
                 'library_name', 'run_name', 'run_block_name', 'paired_length',
                 'library_layout');
  foreach my $method(@methods){
    print $object->$method."\t";
  }
  print $paired_file."\t";
  print $withdrawn."\t";
  print $time."\t";
  print $comment."\t";
  print $read_count."\t";
  print $run_count."\t";
  print $analysis_group."\n";
  
}


sub standard_index_methods{
  return ['run_id', 'study_id', 'study_name', 'center_name', 'submission_id', 
          'submission_date', 'sample_id', 'sample_name', 'population', 
          'experiment_id', 'instrument_platform', 'instrument_model', 
          'library_name', 'run_name', 'run_block_name', 'paired_length',
          'library_layout']
}


=head2 assign_files

  Arg [1]   : Arrayref of either ReseqTrack::File objects or filename strings
  Arg [2]   : optional, arrayref of regular expressions
  Function  : assigns files as mate1, mate2 or frag based on their filename
  Returntype: arrayref of either ReseqTrack::File objects or filename strings, depends on input
              The return order is mate1, mate2, frag (for the default regular expresions)
  Example   : ($mate1, $mate2, $frag) = assign_files(\@files);

=cut

sub assign_files{
  my ($files, $regexs) = @_;
  if (! $regexs) {
      my @regexs = (qr/[ES]RR\d+_1\.(\w+\.)*f(?:ast)?q(?:\.gz)?/i,
                    qr/[ES]RR\d+_2\.(\w+\.)*f(?:astq)?(?:\.gz)?/i,
                    qr/[ES]RR\d+\.(\w+\.)*f(?:ast)?q(?:\.gz)?/i);
#     my @regexs = (qr/(_1\.fastq\.gz)/i,
#		   qr/(_2\.fastq\.gz)/i,
#		   qr/(\.fastq\.gz)/i);
     $regexs = \@regexs;
  }

  my @return_files;
  foreach my $file(@$files){
    my $filename = (ref $file eq 'ReseqTrack::File') ? $file->name : $file;
    my $match_found = 0;
    REGEX:
    foreach my $i (0..@$regexs-1) {
	#print "pattern " . $regexs->[$i] . "\n";
        if ($filename =~ $regexs->[$i]) {
            throw("More than one file matched " . $regexs->[$i]) if $return_files[$i];
            $return_files[$i] = $file;
            $match_found = 1;
            last REGEX;
        }
    }
    throw("File did not match any regular expression: $filename") if (!$match_found);
  }

  #this returns ($mate1, $mate2, $frag) when default regexs are used
  return @return_files;
}


1;
