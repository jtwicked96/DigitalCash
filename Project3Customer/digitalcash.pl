#!/bin/perl
#Written by Joshua Wilson
use strict;
use warnings;
use 5.010; #semi-new version of perl
use autodie; #provides a convenient way to replace functions that normally return false on failure with equivalents that throw an exception on failure.



use Data::Dumper; #takes a variable ( or reference to a variable) and 'unrolls' or dumps it out for inspection
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev); #parses the command line, recognizing and removing specific options and their possible values.
use POSIX; #POSIX module permits you to access all (or nearly all) the standard POSIX 1003.1 identifiers.
use Math::BigInt; #makes the program run faster with huge numbers

use JSON; #using JSON for read/write purposes, to/from JSON files (instead of .txt)
my $json = JSON->new()->pretty([1]); #proper spacing and indentation for JSON files 


my $user; #user.properties file variable (user ID)
my $bank; #bank.properties file variable (e=29,n=571,d=59)
my $create_random; #used to create a randomly generated number file, with the name of your choosing (filename.properties)
my $use_random; #used to apply the randomly generated number file (filename.properties) against the Money Order file (orders.json)

my $orders; #money Orders variable 
my $blinded_orders; #already blinded Money Orders variable
my $signed_blinded_orders; #placeholder for signed blinded orders
my $signed_unblinded_orders; #placeholder for signed unblinded orders
my $signed_blinded_orders_revealed_halfs; #placeholder for revealed halves
my $order_output; #blinded money order output variable


GetOptions( 
#allows for the following flags to be set when running the program/tool in a CLI environment 
#random number file needs to be generated first, and options should be used in the following order when running this program: 
#1.(path needs to be set to digitalcash.pl directory), 
#2."perl digitalcash.pl -u user.properties -b bank.properties -c random_filename" (creates randomly generated numbers file)
#3."perl digitalcash.pl -u user.properties -b bank.properties -r random_filename.properties -o orders.json -O orderoutput.json (performs S/S, B/C, Blinding, and creates the final blinded money order file)
	
	'user|u=s' => \$user, #-u user.properties
	'bank|b=s' => \$bank, #-b bank.properties
	'create-random|c=s' => \$create_random, #-c create random_filename
	'use-random|r=s' => \$use_random, #-r use random_filename
	'orders|o=s' => \$orders, #-o orders.json
	'order-output|O=s' => \$order_output, #-O orderoutput.json
	'blinded|B=s' => \$blinded_orders, #-B option for an already blinded money order file (no functionality yet)
	'signed|s=s' => \$signed_blinded_orders, #-s option for a signed blinded order file (no functionality yet)
	'unblind|U=s' => \$signed_unblinded_orders, #-U option to unblind a money order file (no functionality yet)
	'revealed|R=s' => \$signed_blinded_orders_revealed_halfs, #-R option for signed blinded orders revealed halves (no functionality yet)
	
);
die "User file not given\n" unless $user; #will kill the program if no user file option is provided
die "Bank file not given\n" unless $bank; #will kill the program if no bank file option is provided

sub read_properties_file{ #subroutine to read .properties files
	my $file = shift;
	my %hash;
	open(my $fh, "<", $file);
	while(my $line = <$fh>){
		chomp $line;
		my @line_parts = split "=", $line;
		$hash{$line_parts[0]} = $line_parts[1];
	}
	close $fh;
	return \%hash;
}

sub read_json_file{ #subroutine to read .json files
	my $file = shift;
	local $/ = undef;
	open(my $fh, "<", $file);
	my $file_content = <$fh>;
	my $object_ref = $json->decode($file_content);
	my @object = @{$object_ref};
	close $fh;
	return \@object;
}

sub write_json_file{ #subroutine to write to .json files 
	my $object_ref = shift;
	my $file_name = shift;
	if($file_name !~ /.json$/){
		$file_name .= ".json";
	}
	if(-e $file_name){
		warn "$file_name already exists\n"; #warns admin if the filename is already in use
	}else{
		open(my $fh, ">", $file_name);
		print $fh $json->encode($object_ref);
		close $fh;
	}
}

my $bank_ref = read_properties_file($bank); #reading from the bank.properties file
my %bank = %{$bank_ref};
my $user_ref = read_properties_file($user); #reading from the user.properties file
my %user = %{$user_ref};

if($create_random){; #if statement allows for the ability to create a file of random numbers through perl's built-in rand() function - used for blinding the money order
	my $keys_ref = read_json_file("keys.json"); #reading from the keys.json file
	my @keys = @{$keys_ref};
	my %keys_hash;
	for my $key(@keys){
		$keys_hash{$key} = ceil(rand(99)); 
	}
	if($create_random !~ /.properties$/){
		$create_random .= ".properties";
	}
	if(-e $create_random){
		die "$create_random already exists\n"; #wont create file if the filename is already in use
	}else{
		open(my $fh, ">", $create_random);
		my @keys2 = keys %keys_hash;
		for my $key(@keys2){
			say $fh $key."=".$keys_hash{$key};
		}
		close $fh;
	}
	exit;
}

die "No random file given\n" unless $use_random; #-r random_filename must be an option
my $num_ref = read_properties_file($use_random);
my %random_numbers = %{$num_ref};

sub blind_value{ #blinding data values
	my $value = shift;
	my $blinding_factor = shift;
	my $blinded_value = Math::BigInt->new($value);
	$blinded_value->bmul($blinding_factor);
	$blinded_value->bmod($bank{n});
	return $blinded_value->numify();
}

if($orders){
	my $order_ref = read_json_file($orders);
	my @orders = @{$order_ref};
	
	#Secret Splitting Algorithm
	my %secret_numbers;
	
	#Order 1
	$secret_numbers{S11} = Math::BigInt->new($user{id});
	$secret_numbers{S11}->bxor($random_numbers{R11});

	$secret_numbers{S12} = Math::BigInt->new($user{id});
	$secret_numbers{S12}->bxor($random_numbers{R12});

	#Order 2
	$secret_numbers{S21} = Math::BigInt->new($user{id});
	$secret_numbers{S21}->bxor($random_numbers{R21});

	$secret_numbers{S22} = Math::BigInt->new($user{id});
	$secret_numbers{S22}->bxor($random_numbers{R22});

	#Order 3
	$secret_numbers{S31} = Math::BigInt->new($user{id});
	$secret_numbers{S31}->bxor($random_numbers{R31});

	$secret_numbers{S32} = Math::BigInt->new($user{id});
	$secret_numbers{S32}->bxor($random_numbers{R32});
	
	my @keys = ( #hardcoded array of random number keys
		[
			["R11","R12","R111","R112","R121","R122"],
			["S11","S12","S111","S112","S121","S122"]
		],
		[
			["R21","R22","R211","R212","R221","R222"],
			["S21","S22","S211","S212","S221","S222"]
		],
		[
			["R31","R32","R311","R312","R321","R322"],
			["S31","S32","S311","S312","S321","S322"]
		]
	);
	
	my @blinded_orders;
	for(my $i = 0;$i < scalar @orders;$i++){
		my $order = $orders[$i];
		my $current_keys_ref = $keys[$i];
		my @current_keys = @{$current_keys_ref};
		my @r = @{$current_keys[0]};
		my @s = @{$current_keys[1]};
		
		my $l1 = Math::BigInt->new($random_numbers{$r[0]});
		$l1->bxor($random_numbers{$r[2]});
		$l1->bxor($random_numbers{$r[3]});
	    
		my $r1 = Math::BigInt->new($secret_numbers{$s[0]});
		$r1->bxor($random_numbers{$s[2]});
		$r1->bxor($random_numbers{$s[3]});

		my $l2 = Math::BigInt->new($random_numbers{$r[1]});
		$l2->bxor($random_numbers{$r[4]});
		$l2->bxor($random_numbers{$r[5]});

		my $r2 = Math::BigInt->new($secret_numbers{$s[1]});
		$r2->bxor($random_numbers{$s[4]});
		$r2->bxor($random_numbers{$s[5]});

		 
		
		my $key_name = "K".($i+1);
		my $k = $random_numbers{$key_name};
		my $blinding_factor = Math::BigInt->new($k);
		$blinding_factor->bmodpow($bank{e}, $bank{n});
		
		my @blinded_order = ( #Blinding Algorithm
			"amount" => blind_value($order->{'amount'}, $blinding_factor),
			"uniq" => blind_value($order->{'uniq'}, $blinding_factor),
			"id" => [
				[
				    [blind_value($l1->numify(), $blinding_factor), blind_value(int $random_numbers{$r[2]}, $blinding_factor)],
				    [blind_value($r1->numify(), $blinding_factor), blind_value(int $random_numbers{$s[2]}, $blinding_factor)]
				],
				[
				    [blind_value($l2->numify(), $blinding_factor), blind_value(int $random_numbers{$r[4]}, $blinding_factor)],
				    [blind_value($r2->numify(), $blinding_factor), blind_value(int $random_numbers{$s[4]}, $blinding_factor)]
				]
			]
		);
		
		push @blinded_orders, \@blinded_order; #pushing the blinded order
	}
	
	write_json_file(\@blinded_orders, $order_output); #Allowing the program to write the blinded money order out to a json file
}
