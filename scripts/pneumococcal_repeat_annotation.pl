
use strict;
use warnings;
use Carp;
use Bio::SeqIO;
use Bio::SeqI;
use Data::Dumper;
use File::Temp;
use File::Copy;
use File::Basename;

my $n = 0;
my %start;
my %end;
my %type;
my %score;
my %strand;
my $r = 0;
my %repeats;
my %BOX;
my $boxstart;
my $boxend;
my $boxnum = 0;
my $boxstrand;
my %boxstart;
my %boxstrand;
my %boxend;
my $A_start;
my $A_end;
my $A_score = 0;
my $A_hitstrand;
my $A_hitstart;
my $A_hitend;
my $B_start;
my $B_end;
my $B_score = 0;
my $B_hitstrand;
my $B_hitstart;
my $B_hitend;
my $in_box = 0;
my $start;
my $end;
my $hitscore = 0;
my $hitstart = 0;
my $hitend = 0;
my $hitstrand = 0;
my %brokencoords;
my %brokenscore;
my %brokendisrupt;

if (!exists($ENV{KB_TOP}))
{
    die "$0: KB_TOP not set in environment - required for this application";
}

my $HMM_DIR = "$ENV{KB_TOP}/libexec/strep_repeats/Repeat_HMMs";
-d $HMM_DIR || die "HMM dir $HMM_DIR not found";

my $HMMLS = "$ENV{KB_TOP}/libexec/strep_repeats/hmmls";
-x $HMMLS || die "hmmls not fount at $HMMLS";

my $tmpdir = File::Temp::tempdir(undef, CLEANUP => 1);

my @repeats = ("boxA","boxB","boxC","RUP","SPRITE");				# repeats being analysed
my %cutoffs = (									# cutoff scores for HMM analysis
		"boxA" => 30,
		"boxB" => 14,
		"boxC" => 28,
		"RUP" => 47,
		"SPRITE" => 66,
);
my %hmms = (
		"boxA" => "$HMM_DIR/boxA.hmm",			# paths of HMM for analysis
		"boxB" => "$HMM_DIR/boxB.hmm",
		"boxC" => "$HMM_DIR/boxC.hmm",
		"RUP" => "$HMM_DIR/RUP.hmm",
		"SPRITE" => "$HMM_DIR/SPRITE.hmm",
);
my %input_files = (
		"boxA" => "boxA.rep",						# output files from HMM analysis
		"boxB" => "boxB.rep",
		"boxC" => "boxC.rep",
		"RUP" => "RUP.rep",
		"SPRITE" => "SPRITE.rep",
);

#
# Read from the one file if it is there, or STDIN otherwise.
#

my $input_file;

if (@ARGV == 0)
{
    $input_file = "$tmpdir/input_file";
    copy(\*STDIN, $input_file);
}
elsif (@ARGV == 1)
{
    $input_file = $ARGV[0];
}
else
{
    die "Usage: $0 [input-file] > output\n";
}

my $ibase = basename($input_file);

foreach my $repeat (@repeats) {

    print STDERR "Searching sequence $input_file for repeat $repeat...";
    run_system("$HMMLS -c -t $cutoffs{$repeat} $hmms{$repeat} $input_file > $tmpdir/$ibase.$input_files{$repeat}");
    print STDERR "done\n";
}

open(OUT, ">&STDOUT") or confess "Cannot reopen STDOUT: $!";

{
    my $genome = $input_file;
    foreach my $repeat (sort keys %input_files) {						# parse information from HMM output
	open(IN, "<", "$tmpdir/$ibase.$input_files{$repeat}") or
	    confess "Cannot open input file $tmpdir/$ibase.$input_files{$repeat}: $!";
	foreach (<IN>) {
	    chomp;
	    if (my ($score) = /^(\d+\.\d+)/) {
		$score = $1;
		my ($start, $end) = /\sf\:\s*(\d+)\s+t\:\s*(\d+)/;
		if (($score > $cutoffs{$repeat}) && $start && $end) {
		    $start{$r} = $start;
		    $end{$r}   = $end;
		    $type{$r}  = $repeat;
		    $score{$r} = $score;
		    
		    if ($end{$r} && $start{$r} && ($end{$r} > $start{$r})) {
			$strand{$r} = 1;	
		    } else {
			$strand{$r} = -1;
		    }	
		}
		$r++;
	    }
	}
    }
    print STDERR "Identified repeat units in sequence $genome\n";
    foreach my $repeata (sort keys %start) { # identify composite BOX elements from box modules
	if ($type{$repeata} =~ /boxA/) {
	    $boxstrand = $strand{$repeata};
	    $boxstart = $start{$repeata};
	    @{$BOX{$boxnum}} = "$repeata";
	    if ($boxstrand == 1) {
		$boxend = $end{$repeata}+5; # five base leeway for finding the adjacent boxB element
		foreach my $repeatb (sort {$start{$a} <=> $start{$b}} keys %start) {
		    if ($type{$repeatb} =~ /boxB/ && ($start{$repeatb} <= $boxend && $start{$repeatb} >= $boxstart) && $strand{$repeatb} == $boxstrand) {
			$boxend = $end{$repeatb}+1;
			push(@{$BOX{$boxnum}},$repeatb);
		    }
		}
		foreach my $repeatc (sort {$start{$a} <=> $start{$b}} keys %start) {
		    if ($type{$repeatc} =~ /boxC/ && ($start{$repeatc} <= $boxend && $start{$repeatc} >= $boxstart) && $strand{$repeatc} == $boxstrand) {
			$boxend = $end{$repeatc}+1;
			push(@{$BOX{$boxnum}},$repeatc);
		    }
		}
		if ($#{$BOX{$boxnum}} > 0) {
		    $boxstart{$boxnum} = $boxstart;
		    $boxend{$boxnum} = $boxend-1;
		    $boxstrand{$boxnum} = $boxstrand;
		    $boxnum++;
		}
	    } else {
		$boxend = $end{$repeata}-5;
		foreach my $repeatb (sort {$start{$b} <=> $start{$a}} keys %start) {
		    if ($type{$repeatb} =~ /boxB/ && ($start{$repeatb} >= $boxend && $start{$repeatb} <= $boxstart) && $strand{$repeatb} == $boxstrand) {
			$boxend = $end{$repeatb}-1;
			push(@{$BOX{$boxnum}},$repeatb);
		    }
		}
		foreach my $repeatc (sort {$start{$b} <=> $start{$a}} keys %start) {
		    if ($type{$repeatc} =~ /boxC/ && ($start{$repeatc} >= $boxend && $start{$repeatc} <= $boxstart) && $strand{$repeatc} == $boxstrand) {
			$boxend = $end{$repeatc}-1;
			push(@{$BOX{$boxnum}},$repeatc);
		    }
		}
		if ($#{$BOX{$boxnum}} > 0) {
		    $boxstart{$boxnum} = $boxstart;
		    $boxend{$boxnum} = $boxend+1;
		    $boxstrand{$boxnum} = $boxstrand;
		    $boxnum++;
		}
	    }
	}
    }
    $in_box = 0;
    foreach my $repeatc (sort keys %start) { # find BC BOX elements with no starting boxA module
	if ($type{$repeatc} =~ /boxC/) {
	    foreach $boxnum (sort keys %BOX) {
		if (grep(/$repeatc/,@{$BOX{$boxnum}})) {
		    $in_box = 1;
		}
	    }
	    if ($in_box == 0) {
		$boxend = $end{$repeatc};
		$boxstrand = $strand{$repeatc};
		@{$BOX{$boxnum}} = "$repeatc";
		if ($boxstrand == -1) {
		    $boxstart = $start{$repeatc}+1;
		    foreach my $repeatb (sort {$start{$a} <=> $start{$b}} keys %start) {
			if ($type{$repeatb} =~ /boxB/ && ($end{$repeatb} <= $boxstart && $start{$repeatb} >= $boxstart) && $strand{$repeatb} == $boxstrand) {
			    $boxstart = $start{$repeatb}+1;
			    push(@{$BOX{$boxnum}},$repeatb);
			}	
		    }
		    if ($#{$BOX{$boxnum}} > 0) {
			$boxstart{$boxnum} = $boxstart-1;
			$boxend{$boxnum} = $boxend;
			$boxstrand{$boxnum} = $boxstrand;
			$boxnum++;
		    }
		} else {
		    $boxstart = $start{$repeatc}-1;
		    foreach my $repeatb (sort {$start{$b} <=> $start{$a}} keys %start) {
			if ($type{$repeatb} =~ /boxB/ && ($end{$repeatb} >= $boxstart && $start{$repeatb} <= $boxstart) && $strand{$repeatb} == $boxstrand) {
			    $boxstart = $start{$repeatb}-1;
			    push(@{$BOX{$boxnum}},$repeatb);
			}
		    }
		    if ($#{$BOX{$boxnum}} > 0) {
			$boxstart{$boxnum} = $boxstart+1;
			$boxend{$boxnum} = $boxend;
			$boxstrand{$boxnum} = $boxstrand;
			$boxnum++;
		    }
		}
	    }
	    $in_box = 0;
	}
    }
    print STDERR "Identified composite BOX elements\n";
    delete($BOX{$boxnum});
    
    my %overlaps;
    
    foreach my $repeata (sort keys %start) {
	# identify overlapping repeat elements, except BOX modules
	foreach my $repeatb (sort keys %start) {
	    if (($start{$repeatb} <= $start{$repeata} && $end{$repeatb} >= $start{$repeata}) || ($start{$repeatb} <= $end{$repeata} && $end{$repeatb} >= $end{$repeata})) {
		unless (($type{$repeata} =~ /box/ && $type{$repeatb} =~ /box/) || ($repeata == $repeatb)) {
		    my @unsorted = ($repeata,$repeatb);
		    my @sorted = sort(@unsorted);
		    $overlaps{$sorted[0]} = $sorted[1];
		}		
	    }
	}
    }
    
    print STDERR "Realigning overlapping elements\n";
    
    my $fasta = Bio::SeqIO->new(-file=>$genome, -format=>"fasta");
    my $sequence = $fasta->next_seq;
    
    foreach my $repeata (sort keys %overlaps) {
	# rescan regions around overlapping repeats to look for disruptions
	boundaries($repeata);
	$A_start = $start;
	$A_end = $end;
	my $upper_bound = $end+251;
	my $lower_bound = $start-251;
	my $lower_seq = $sequence->subseq($lower_bound,$start-1);
	my $upper_seq = $sequence->subseq($end+1,$upper_bound);
	my $total_seq = "$lower_seq"."$upper_seq";
	print_fasta("$tmpdir/first.seq",$total_seq);
	run_system("$HMMLS -c $hmms{$type{$overlaps{$repeata}}} $tmpdir/first.seq > $tmpdir/first.out");
	hmm_results("$tmpdir/first.out");
	$A_score = $hitscore;
	$A_hitstrand = $hitstrand;
	$A_hitstart = $hitstart;
	$A_hitend = $hitend;
	boundaries($overlaps{$repeata});
	$B_start = $start;
	$B_end = $end;
	$upper_bound = $end+251;
	$lower_bound = $start-251;
	$lower_seq = $sequence->subseq($lower_bound,$start-1);
	$upper_seq = $sequence->subseq($end+1,$upper_bound);
	$total_seq = "$lower_seq"."$upper_seq";
	print_fasta("$tmpdir/second.seq",$total_seq);
	run_system("$HMMLS -c $hmms{$type{$repeata}} $tmpdir/second.seq > $tmpdir/second.out");	
	hmm_results("$tmpdir/second.out");
	$B_score = $hitscore;
	$B_hitstrand = $hitstrand;
	$B_hitstart = $hitstart;
	$B_hitend = $hitend;
	my $A_inc = ($A_score - $score{$overlaps{$repeata}})/$score{$overlaps{$repeata}};
	my $B_inc = ($B_score - $score{$repeata})/$score{$repeata};
	if ($A_inc >= 0 || $B_inc >= 0) { # identify disruption events
	    my $firstpoint; my $secondpoint; my $thirdpoint; my $fourthpoint;
	    if ($A_inc > $B_inc) {
		$start{$overlaps{$repeata}} = "BROKEN";
		if ($A_hitstrand == 1) {
		    $secondpoint = $A_start-1;
		    $thirdpoint = $A_end+1;
		    $firstpoint = $A_start-252+$A_hitstart;
		    $fourthpoint = $A_end-251+$A_hitend;
		    @{$brokencoords{$overlaps{$repeata}}} = ($firstpoint,$secondpoint,$thirdpoint,$fourthpoint);
		    if ($type{$repeata} =~ /box/) {$brokendisrupt{$overlaps{$repeata}} = "BOX";} else {$brokendisrupt{$overlaps{$repeata}} = $type{$repeata};}
		    $brokenscore{$overlaps{$repeata}} = $A_score;
		} else {
		    $secondpoint = $A_start-1;
		    $thirdpoint = $A_end+1;
		    $firstpoint = $A_start-252+$A_hitend;
		    $fourthpoint = $A_end-251+$A_hitstart;
		    @{$brokencoords{$overlaps{$repeata}}} = ($firstpoint,$secondpoint,$thirdpoint,$fourthpoint);
		    if ($type{$repeata} =~ /box/) {$brokendisrupt{$overlaps{$repeata}} = "BOX";} else {$brokendisrupt{$overlaps{$repeata}} = $type{$repeata};}
		    $brokenscore{$overlaps{$repeata}} = $A_score;
		}
	    } elsif ($B_inc > $A_inc) {
		$start{$repeata} = "BROKEN";
		if ($B_hitstrand == 1) {
		    $secondpoint = $B_start-1;
		    $thirdpoint = $B_end+1;
		    $firstpoint = $B_start-252+$B_hitstart;
		    $fourthpoint = $B_end-251+$B_hitend;
		    @{$brokencoords{$repeata}} = ($firstpoint,$secondpoint,$thirdpoint,$fourthpoint);
		    if ($type{$overlaps{$repeata}} =~ /box/) {$brokendisrupt{$repeata} = "BOX";} else {$brokendisrupt{$repeata} = $type{$overlaps{$repeata}};}
		    $brokenscore{$repeata} = $B_score;
		} else {
		    $secondpoint = $B_start-1;
		    $thirdpoint = $B_end+1;
		    $firstpoint = $B_start-252+$B_hitend;
		    $fourthpoint = $B_end-251+$B_hitstart;
		    @{$brokencoords{$repeata}} = ($firstpoint,$secondpoint,$thirdpoint,$fourthpoint);
		    if ($type{$overlaps{$repeata}} =~ /box/) {$brokendisrupt{$repeata} = "BOX";} else {$brokendisrupt{$repeata} = $type{$overlaps{$repeata}};}
		    $brokenscore{$repeata} = $B_score;
		}
	    }
	}
	
    }
    
    print STDERR "Disrupted repeat elements identified\n";
    
    foreach my $repeat (sort keys %start) {
	if ($start{$repeat} && ($start{$repeat} eq "BROKEN")) {
	    if ($strand{$repeat} == 1) {
		print OUT "FT   repeat_unit     order(${$brokencoords{$repeat}}[0]..${$brokencoords{$repeat}}[1],${$brokencoords{$repeat}}[2]..${$brokencoords{$repeat}}[3])\n";
	    } elsif ($strand{$repeat} == -1) {
		print OUT "FT   repeat_unit     complement(${$brokencoords{$repeat}}[0]..${$brokencoords{$repeat}}[1],${$brokencoords{$repeat}}[2]..${$brokencoords{$repeat}}[3])\n";
	    }
	    print OUT "FT                   /colour=2\n";
	    print OUT "FT                   /label=$type{$repeat}\n";
	    print OUT "FT                   /note=Detected using HMMER $HMMLS; appears to have been disrupted through $brokendisrupt{$repeat} insertion\n";
	    print OUT "FT                   /note=Initial match of score $score{$repeat} to model $type{$repeat}; realignment score of $brokenscore{$repeat}\n";
	} else {
	    if ($strand{$repeat} == 1) {
		print OUT "FT   repeat_unit     $start{$repeat}..$end{$repeat}\n";
	    } elsif ($strand{$repeat} == -1) {
		print OUT "FT   repeat_unit     complement($start{$repeat}..$end{$repeat})\n";
	    }
	    print OUT "FT                   /colour=2\n";
	    print OUT "FT                   /label=$type{$repeat}\n";
	    print OUT "FT                   /note=Detected using HMMER $HMMLS; match of score $score{$repeat} to model $type{$repeat}\n";
	}
    }
    foreach my $boxnum (sort keys %BOX) {
	if ($boxstrand{$boxnum} == 1) {
	    print OUT "FT   repeat_unit     $boxstart{$boxnum}..$boxend{$boxnum}\n";
	} else {
	    print OUT "FT   repeat_unit     complement($boxstart{$boxnum}..$boxend{$boxnum})\n";
	}
	print OUT "FT                   /colour=4\n";
	print OUT "FT                   /note=Composite BOX element\n";
	print OUT "FT                   /label=BOX\n";
    }
    
    undef(%start);
    undef(%end);
    undef(%type);
    undef(%score);
    undef(%strand);
    undef(%repeats);
    undef(%BOX);
    undef(%boxstart);
    undef(%boxstrand);
    undef(%boxend);
    undef(%brokencoords);
    undef(%brokenscore);
    undef(%brokendisrupt);	
}

print STDERR "Done\n";

sub boundaries {											# subroutine for identifying repeat boundaries, esp BOX elements
	my $rep = shift;
	if ($type{$rep} =~ /box/) {
		foreach $boxnum (sort keys %BOX) {
			foreach my $module (@{$BOX{$boxnum}}) {
				if ($module == $rep) {
					my @unsorted = ("$boxstart{$boxnum}","$boxend{$boxnum}");
					my @sorted = sort(@unsorted);
					$start = $sorted[0];
					$end = $sorted[1];
					$in_box = 1;
				}
			}
		}
	}
	if ($in_box == 0) {
		my @unsorted = ("$start{$rep}","$end{$rep}");
		my @sorted = sort(@unsorted);
		$start = $sorted[0];
		$end = $sorted[1];
	}
	$in_box = 0;
	return($start,$end);
}

sub print_fasta {
# subroutine for printing sequence in a suitable format for hmmls
    my $filename = shift;
    my $dna_string = shift;
    my $fh;
    open($fh, ">", $filename) or confess "Cannot open $filename: $!";
    print $fh ">$filename\n";
    my $offset = 0;
    while ($offset < 440) {
	my $line = substr($dna_string,$offset,60);
	print $fh "$line\n";
	$offset+=60;
    }
    my $line = substr($dna_string,$offset,(500-$offset));
    print $fh "$line\n";
    close $fh;
 }

sub hmm_results {											# subroutine for picking the top hit from the hmmls results
	my $filename = shift;
	open(HMM, "<", $filename) or confess "Cannot open HMM file $filename: $!";
	$hitscore = 0;
	foreach (<HMM>) {
		my @data = split(/\s+/,$_);
		if (substr($_,0,2) =~ /\d\d/) {
			if ($data[0] > $hitscore) {
				if ($data[3] < $data[5] && $data[3] <= 250 && $data[5] >= 250) {
					$hitstrand = 1;
					$hitscore = $data[0];
					$hitstart = $data[3];
					$hitend = $data[5];
				} elsif ($data[5] < $data[3] && $data[3] >= 250 && $data[5] <= 250) {
					$hitstrand = -1;
					$hitscore = $data[0];
					$hitstart = $data[3];
					$hitend = $data[5];
				}
			}
		}
	}
	close HMM;
	return($hitstart,$hitend,$hitscore,$hitstrand);
}

sub run_system
{
    my(@cmd) = @_;

    my $rc = system(@cmd);
    if ($rc != 0)
    {
	confess "Command failed with rc=$rc: @cmd";
    }
}
