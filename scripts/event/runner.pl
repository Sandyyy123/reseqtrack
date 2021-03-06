#!/usr/bin/env perl

=pod

=head1 NAME

ReseqTrack/scripts/event/runner.pl

=head1 SYNOPSIS

This script is used by the event pipeline system to run the event associated with
a particular job or set of jobs

=head1 OPTIONS

-dbhost, host name for database instance

-dbname, name of database on instance

-dbuser, name of user

-dbpass, password string if required

-dbport, the port number of the database instance

-print_job_info, flag to print out job info from the batch submission system

-clean_up_output, flag to delete the output file if job executes successfully


=head1 Examples

perl /homes/laura/code/1000genomes/ReseqTrack/scripts/event/runner.pl -dbhost mysql-g1kdcc -dbuser g1krw -dbpass thousandgenomes -dbport 4197 -dbname lec_era_meta_info -name fetch _archive_fastq -print_job_info -clean_up_output 15258

=head2 Other useful scripts

ReseqTrack/event/run_event_pipeline.pl, this is the script for creating job objects to run on the farm and running them.

=cut

use strict;
use warnings;

use ReseqTrack::DBSQL::DBAdaptor;
use ReseqTrack::EventComplete;
use ReseqTrack::Tools::Exception;
use ReseqTrack::Tools::FileSystemUtils qw( delete_file );
use ReseqTrack::Tools::PipelineUtils qw( create_event_commandline setup_batch_submission_system );
use ReseqTrack::Tools::GeneralUtils qw( execute_system_command );
use Getopt::Long;
use Sys::Hostname;
use File::Basename;
#use IO::Select;
use POSIX;

my $term_sig =  0;
$SIG{TERM} = \&termhandler;
$SIG{INT} = \&termhandler;

my $dbhost;
my $dbuser;
my $dbpass;
my $dbport = 3306;
my $dbname;
my $logic_name;
my @input_strings;
my $print_job_info;
my $clean_up_output;
my $batch_submission_path = 'ReseqTrack::Tools::BatchSubmission';
my $batch_submission_module_name = 'LSF';

my $runner_script = $0;
my $commandline = "$runner_script @ARGV";
my $submission_index = $ENV{'LSB_JOBINDEX'};
my $submission_id = $ENV{'LSB_JOBID'};

print "$commandline\n";
print "LSB_JOBINDEX: $submission_index\n";
print "\n\n";

&GetOptions(
    'dbhost=s' => \$dbhost,
    'dbname=s' => \$dbname,
    'dbuser=s' => \$dbuser,
    'dbpass=s' => \$dbpass,
    'dbport=s' => \$dbport,
    'name=s'   => \$logic_name,
    'print_job_info' => \$print_job_info,
    'clean_up_output' => \$clean_up_output,
    'batch_submission_path=s' => \$batch_submission_path,
    'batch_submission_module_name:s' => \$batch_submission_module_name,
);


my $db = ReseqTrack::DBSQL::DBAdaptor->new(
    -host   => $dbhost,
    -user   => $dbuser,
    -port   => $dbport,
    -dbname => $dbname,
    -pass   => $dbpass,
);

throw("$runner_script Can't run without a LSB_JOBINDEX")      if (! defined $submission_index);

my $message_prefix = $runner_script;
if ($submission_index) {
    $message_prefix .= "[$submission_index]";
}

throw("$message_prefix Can't run without a LSB_JOBID")      if (! defined $submission_id);
throw("$message_prefix Can't run without a database connection") if (!$db);
throw("$message_prefix Can't run without a logic_name")      if (!$logic_name);

my $dbID = $submission_index ? $ARGV[$submission_index -1] : $ARGV[0];
print "$message_prefix dbID is $dbID\n";
throw("$message_prefix Can't run without a dbID")      if (! defined $dbID);

my $ea = $db->get_EventAdaptor;
my $event = $ea->fetch_by_name($logic_name);
throw("$message_prefix Failed to fetch event with " . $logic_name)      if (!$event);

my $ja = $db->get_JobAdaptor;
my $job = $ja->fetch_by_dbID($dbID);
throw("$message_prefix Failed to fetch job with " . $dbID) if (!$job);
print "$message_prefix input string is ".$job->input_string ."\n";

my $output_file = $job->output_file;
if (! $output_file) {
    my $warning = "$message_prefix Can't run job " . $job->dbID . " " . $job->input_string
             . "without an output file";
    job_failed($job, $warning, $ja);
    throw($warning);
}

open( my $old_stdout, ">&STDOUT") or throw("$message_prefix could not save STDOUT: $!");
open( my $old_stderr, ">&STDERR") or throw("$message_prefix could not save STDERR: $!");

open(my $file_handle, '>>', $output_file) or do {
    my $warning = "$message_prefix Can't open $output_file: $!";
    job_failed($job, $warning, $ja);
    throw($warning);
};

open(STDOUT, ">&", $file_handle) or do {
    my $warning = "$message_prefix Can't redirect STDOUT to $output_file: $!";
    job_failed($job, $warning, $ja);
    throw($warning);
};
open(STDERR, ">&", $file_handle) or do {
    my $warning = "$message_prefix Can't redirect STDERR to $output_file: $!";
    job_failed($job, $warning, $ja);
    throw($warning);
};
print "$commandline\n";
print "LSB_JOBINDEX: $submission_index\n";
print "output for job" . $job->dbID . " " . $job->input_string . "\n";

my $hostname = [split(/\./, hostname())];
my $host = shift(@$hostname);
$job->host($host);
$job->submission_id($submission_id);
$job->submission_index($submission_index);
$ja->update($job);
$job->current_status('WAITING');
$ja->set_status($job);
$ja->update($job);

print "Setting disconnect when inactive to 1\n";
$db->dbc->disconnect_when_inactive(1);

my $input_string = $job->input_string;
$job->current_status('RUNNING');
$ja->set_status($job);

my $cmd = create_event_commandline($event, $input_string);
my $time_elapsed;
my $max_memory;
my $max_swap;

my $oldfh = select(STDOUT);
$| = 1;
select($oldfh);

print "\n*****" . $cmd . "******\n\n";
my $start_time = time;
my $pid = fork;
if (!defined $pid) {
  my $warning = "could not fork: $!";
  job_failed($job, $warning, $ja);
  throw $warning
}
elsif(!$pid) {
  exec($cmd) or do{
    print STDERR "$cmd did not execute: $!\n";
    exit(255);
  }
}

while (! waitpid($pid, WNOHANG)) {
  my ($memory, $vsize) = get_memory($$);
  my $swap = $vsize - $memory;
  $max_memory = $memory if (!$max_memory || $memory > $max_memory);
  $max_swap = $swap if (!$max_swap || $swap > $max_swap);
  sleep(10);
  if ($term_sig) {
    kill 15, $pid;
  }
}
$time_elapsed = time - $start_time;
print "\n**********\n";
if ($term_sig) {
  my $warning = "received a signal";
  job_failed($job, $warning, $ja);
}
elsif (my $signal = $? & 127) {
  my $warning = "process died with signal $signal";
  job_failed($job, $warning, $ja);
}
elsif (my $exit = $? >>8) {
  my $warning = "$cmd exited with value $exit";
  job_failed($job, $warning, $ja);
}
else {
  $job->current_status('SUCCESSFUL');
  $ja->set_status($job);
}


if ($job->current_status eq 'SUCCESSFUL') {
  my $ca               = $db->get_EventCompleteAdaptor;
  my $other_name       = $job->input_string;
  if ($@) {
    my $warning = "could not get memory usage";
    job_failed($job, $warning, $ja);
  }
  $max_memory = int($max_memory/1024 + 0.5);
  $max_swap = int($max_swap/1024 + 0.5);
  my $completed_string = ReseqTrack::EventComplete->new(
      -event        => $event,
      -other_name   => $job->input_string,
      -success      => 0,
      -adaptor      => $ca,
      -time_elapsed => $time_elapsed,
      -exec_host    => $host,
      -memory_usage => $max_memory,
      -swap_usage   => $max_swap,
  );
  eval {
      $ca->store($completed_string);
  };
  if ($@) {
      my $warning =
        "Failed to store " . $input_string . " in completed_string $@";
      job_failed($job, $warning, $ja, 'FAIL_NO_RETRY');
  }

  eval { $ja->remove($job); };
  throw("Failed to remove " . $job . " from " . $dbname . " $@")
    if ($@);

}
if ($print_job_info) {
  print "**********\nBatch job information:\n";
  my $batch_submission_module = $batch_submission_path."::".$batch_submission_module_name;
  my $batch_submission_object = eval {setup_batch_submission_system($batch_submission_module, {})};
  if ($@) {
    print "\nNo job info because package not loaded: $batch_submission_module\n";
    print "runner script will continue to run\n";
  }
  else {
    my $job_info = $batch_submission_object->job_info($submission_id, $submission_index);
    foreach my $line (@$job_info) {
      print $line;
    }
  }
}

if ($clean_up_output && $job->current_status eq 'SUCCESSFUL') {
    open(STDOUT, ">&", $old_stdout) or do {
        my $warning = "$message_prefix Can't restore STDOUT: $!";
        throw($warning);
    };
    open(STDERR, ">&", $old_stderr) or do {
        my $warning = "$message_prefix Can't restore STDERR: $!";
        throw($warning);
    };
    close $file_handle or do {
        my $warning = "$message_prefix Can't close file handle: $!";
        throw($warning);
    };

    my $output_file = $job->output_file;
    delete_file($output_file);
}




sub job_failed {
  my ($job, $warning, $ja, $status) = @_;
  $status = 'FAILED' if (!$status);
  print STDERR $warning . "\n";
  $job->current_status($status);
  $ja->set_status($job);
  $ja->unset_submission_id();
}

sub get_memory{
  my $pid = shift;
  my $ps_line = `ps --no-headers -o rss,vsize --pid $pid`;
  $ps_line =~ s/^\s+//;
  my ($memory, $vsize) = split(/\s+/, $ps_line);
  my ($child_memory, $child_vsize) = get_child_memory($pid);
  $memory += $child_memory;
  $vsize += $child_vsize;
  return $memory, $vsize;
}

sub get_child_memory {
  my $parent_pid = shift;
  my $ps_output = `ps --no-headers -o rss,vsize,pid --ppid $parent_pid`;
  my ($memory, $vsize) = (0,0);
  foreach my $ps_line (split(/\n/, $ps_output)) {
    $ps_line =~ s/^\s+//;
    my ($proc_memory, $proc_vsize, $proc_pid) = split(/\s+/, $ps_line);
    my ($proc_child_memory, $proc_child_vsize) = get_child_memory($proc_pid);
    $memory += $proc_memory + $proc_child_memory;
    $vsize += $proc_vsize + $proc_child_vsize;
  }
  return ($memory, $vsize);
}

sub termhandler {
    $term_sig = 1;
}
