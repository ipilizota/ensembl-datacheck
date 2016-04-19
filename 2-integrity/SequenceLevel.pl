=head1 NAME

  SequenceLevel - A user-defined integrity test on coord_system (type 2 in the healthcheck system)
  
=head1 SYNOPSIS

  $ perl SequenceLevel.pl --species 'homo sapiens' --type 'core'
 
=head1 DESCRIPTION

  --species 'species name'    : String (optional) - Name of the species to test on.
  --type 'type'              : String (optional) - Type of the database to test on.
  
  Database type               : Core
  
If no command line input arguments are given, values from the 'config' file in the main directory will be used.

Checks that there are no contig coordinate systems in the coord_system table that have a
version other than 'NULL' with check_version.
check_dna_attachment tests that a coordinate system with a dna sequence region attached to it
has its coord_system.attrib set to sequence_level.

Perl adaptation of the SequenceLevel.java test.
See: https://github.com/Ensembl/ensj-healthcheck/blob/release/84/src/org/ensembl/healthcheck/testcase/generic/SequenceLevel.java
 
=cut

#!/usr/bin/env perl

use strict;
use warnings;

use File::Spec;
use Getopt::Long;

use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Utils::SqlHelper;

use Logger;
use DBUtils::RowCounter;
use DBUtils::Connect;

my $dba = DBUtils::Connect::get_db_adaptor();

my $species = DBUtils::Connect::get_db_species($dba);
my $database_type = $dba->group();

my $log = Logger->new({
    healthcheck => 'SequenceLevel',
    type => $database_type,
    species => $species,
});

my $helper = Bio::EnsEMBL::Utils::SqlHelper->new(
    -DB_CONNECTION => $dba->dbc()
);

my $result = 1;

if(lc($database_type) ne 'core'){
    $log->message("WARNING: this healthcheck only applies to core databases. Problems in execution will likely arise");
}

$result &= check_version($helper, $log);

$result &= check_dna_attachment($helper, $log);

$log->result($result);


sub check_version{
    my ($helper, $log) = @_;
    
    my $sql = "SELECT count(*) FROM coord_system "
		. "WHERE name = 'contig' AND version is not NULL";

    my $rows = DBUtils::RowCounter::get_row_count({
	helper => $helper,
	sql => $sql,
    });
    
    if($rows > 0){
	$log->message("PROBLEM: Some contigs in the coord_system table have a version that is not NULL");
	return 0;
    }
    return 1;    
}

sub check_dna_attachment{
    my ($helper, $log) = @_;
    
    my $dna_result = 1;
    
    my $sql = "SELECT cs.name, COUNT(1) FROM coord_system cs, seq_region s, dna d "
		. "WHERE d.seq_region_id = s.seq_region_id "
		. "AND cs.coord_system_id = s.coord_system_id "
		. "AND cs.attrib NOT LIKE '%sequence_level%' "
		. "GROUP BY cs.coord_system_id";
		
    my $loose_systems = $helper->execute(
			-SQL => $sql,
		     );
    my @loose_systems = @{ $loose_systems };
    
    foreach my $loose_system (@loose_systems){
	$dna_result &= 0;
	my $coord_system = $loose_system->[0];
	my $rows = $loose_system->[1];
	
	$log->message("PROBLEM: Coordinate system $coord_system has $rows seq regions containing sequence, "
			. "but it does not have the sequence_level attribute");
    }
    
    return $dna_result;
}