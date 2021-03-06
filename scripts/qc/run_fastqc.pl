#!/usr/bin/env perl
use strict;
use warnings;

use ReseqTrack::Tools::AttributeUtils;
use ReseqTrack::Tools::QC::FastQC;
use ReseqTrack::Tools::HostUtils qw(get_host_object);
use ReseqTrack::Tools::AttributeUtils;
use ReseqTrack::Tools::FileUtils;
use ReseqTrack::Tools::FileSystemUtils;
use ReseqTrack::DBSQL::DBAdaptor;
use ReseqTrack::Tools::Exception;
use ReseqTrack::Tools::SequenceIndexUtils;
use ReseqTrack::Tools::Loader::File;
use ReseqTrack::Tools::RunMetaInfoUtils qw(create_directory_path);
use Getopt::Long;
use File::Copy;
use File::Path qw(make_path);

use Data::Dumper;

my ($dbhost, $dbuser, $dbpass, $dbname, $dbport);
my $collection_name;
my $collection_type;
my $output_dir;
my $host_name = '1000genomes.ebi.ac.uk';
my $fastqc_path = 'fastqc';
my $directory_layout;
my $report_output_type = 'FASTQC_REPORT';
my $summary_output_type = 'FASTQC_SUMMARY';
my $zip_output_type = 'FASTQC_ZIP';

&GetOptions(
	'dbhost=s'     => \$dbhost,
	'dbname=s'     => \$dbname,
	'dbuser=s'     => \$dbuser,
	'dbpass=s'     => \$dbpass,
	'dbport=s'     => \$dbport,
	'collection_name=s' => \$collection_name,
	'output_dir=s' => \$output_dir,
	'host_name=s' => => \$host_name,
	'collection_type=s' => \$collection_type,
	'program=s' => \$fastqc_path,
	'directory_layout=s' => \$directory_layout,
	'report_output_type=s' => \$report_output_type,
	'summary_output_type=s' => \$summary_output_type,
	'zip_output_type=s' => \$zip_output_type, 
);
	

#Creating database connection
my $db = ReseqTrack::DBSQL::DBAdaptor->new(
	-host => $dbhost,
	-user => $dbuser,
	-port => $dbport,
	-dbname => $dbname,
	-pass => $dbpass,
);

unless($db){
  throw("Can't run without a database");
}

#Need run id and collection type to get required files and meta info
unless($collection_name && $collection_type){
  throw("Can't run without a collection name and a collection type");
}

my $ca = $db->get_CollectionAdaptor;
my $file_adaptor = $db->get_FileAdaptor;
my $collection = $ca->fetch_by_name_and_type($collection_name, $collection_type);

throw("Failed to find a collection for $collection_name $collection_type from ".$ca->dbc->dbname) 
  unless($collection);

throw("output_dir must be specified") unless ($output_dir);


my $rmia = $db->get_RunMetaInfoAdaptor;
my $run_meta_info = $rmia->fetch_by_run_id($collection_name);

if ($run_meta_info && $directory_layout) {
	$output_dir = create_directory_path($run_meta_info, $directory_layout, $output_dir);
}

if (! -d $output_dir) {
	make_path($output_dir) or throw("Could not create output dir $output_dir");
}

my @input_files = map {$_->name} @{$collection->others};

my @summary_files;
my @report_files;
my @zip_files;

for my $fastq_file (@{$collection->others}) {
	$db->dbc->disconnect_when_inactive(1);
	my $fastqc = ReseqTrack::Tools::QC::FastQC->new(
		-program => $fastqc_path,
		-keep_text => 1,
		-keep_summary => 1,
		-keep_zip => 1,
		-working_dir => $output_dir,
		-input_files => [$fastq_file->name],
	);
	
	$fastqc->run;
	$db->dbc->disconnect_when_inactive(0);

        my @summary_paths = grep { /_summary\.txt$/ } @{$fastqc->output_files};
        my @report_paths = grep { /_report\.txt$/ } @{$fastqc->output_files};
        my @zip_paths = grep { /\.zip$/ } @{$fastqc->output_files};

        throw("unexpected number of summary paths: " . scalar @summary_paths) if @summary_paths != 1;
        throw("unexpected number of report paths: " . scalar @report_paths) if @report_paths != 1;
        throw("unexpected number of zip paths: " . scalar @zip_paths) if @zip_paths != 1;
        my ($summary_path, $report_path, $zip_path) = ($summary_paths[0], $report_paths[0], $zip_paths[0]);
	
	push @summary_files, $summary_path;
	push @report_files, $report_path;
	push @zip_files, $zip_path;

	
	my $statistics = $fastq_file->attributes;
	
	open (my $summary_fh, '<', $summary_path) or throw("Could not open $summary_path - odd as we should have just made it");
	while (<$summary_fh>){
		chomp;
		my ($value,$key,$name) = split /\t/;
		push @$statistics, create_attribute_for_object($fastq_file,"FASTQC:$key",$value) if ($value && $key);
	}
	
	$fastq_file->uniquify_attributes($statistics);
	$file_adaptor->store_attributes($fastq_file);
}

create_output_records($collection->name,$summary_output_type,\@summary_files);
create_output_records($collection->name,$report_output_type,\@report_files);
create_output_records($collection->name,$zip_output_type,\@zip_files);

sub create_output_records {
	my ($collection_name,$type,$file_names) = @_;
	
	#create a File loader object for the files
	my $loader = ReseqTrack::Tools::Loader::File->new
	  (
	   -file => $file_names,
	   -do_md5 => 1,
	   -hostname => $host_name,
	   -db => $db,
	   -assign_types => 0,
	   -check_types => 0,
	   -type => $type,
	   -update_existing => 1,
	  );
	#Load the files into the database
	$loader->process_input();
	$loader->create_objects();
	$loader->sanity_check_objects();
	my $file_objects = $loader->load_objects();
	
	my $collection = ReseqTrack::Collection->new(
	  -name => $collection_name,
      -others => $file_objects,
      -type => $type,
      -table_name => 'file',
    );

	$db->get_CollectionAdaptor->store($collection);
}




