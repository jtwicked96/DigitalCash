#!/bin/perl
use strict;
use warnings;
use 5.010;
use autodie;

use Data::Dumper; 
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev); 
use Math::BigInt;
use POSIX;

use JSON;
my $json = JSON->new()->pretty([1]);

my $bank;
my $user;
my $create_random;
my $use_random;

my $orders;
my $blinded_orders;
my $signed_blinded_orders;
my $signed_unblinded_orders;
my $signed_blinded_orders_revealed_halfs;
my $order_output;
GetOptions(
	'bank|b=s' => \$bank,
	'user|u=s' => \$user,
	'create-random|c=s' => \$create_random,
	'use-random|r=s' => \$use_random,
	'orders|o=s' => \$orders,
	'blinded|B=s' => \$blinded_orders,
	'signed|s=s' => \$signed_blinded_orders,
	'unblined|U=s' => \$signed_unblinded_orders,
	'revealed|R=s' => \$signed_blinded_orders_revealed_halfs,
	'order-output|O=s' => \$order_output,
);
die "User file not given\n" unless $user;
die "Bank file not given\n" unless $bank;

sub read_properties_file{
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

sub read_json_file{
	my $file = shift;
	local $/ = undef;
	open(my $fh, "<", $file);
	my $file_content = <$fh>;
	my $object_ref = $json->decode($file_content);
	my @object = @{$object_ref};
	close $fh;
	return \@object;
}

sub write_json_file{
	my $object_ref = shift;
	my $file_name = shift;
	if($file_name !~ /.json$/){
		$file_name .= ".json";
	}
	if(-e $file_name){
		warn "$file_name already exists\n";
	}else{
		open(my $fh, ">", $file_name);
		print $fh $json->encode($object_ref);
		close $fh;
	}
}

my $bank_ref = read_properties_file($bank);
my %bank = %{$bank_ref};
my $user_ref = read_properties_file($user);
my %user = %{$user_ref};

if($create_random){;
	my $keys_ref = read_json_file("keys.json");
	my @keys = @{$keys_ref};
	my %keys_hash;
	for my $key(@keys){
		$keys_hash{$key} = ceil(rand(99));
	}
	if($create_random !~ /.properties$/){
		$create_random .= ".properties";
	}
	if(-e $create_random){
		die "$create_random already exists\n";
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

die "No random file given\n" unless $use_random;
my $num_ref = read_properties_file($use_random);
my %random_numbers = %{$num_ref};

sub blind_value{
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
	
	# Secret Splitting
	my %secret_numbers;
	# Order 1
	$secret_numbers{S11} = Math::BigInt->new($user{id});
	$secret_numbers{S11}->bxor($random_numbers{R11});

	$secret_numbers{S12} = Math::BigInt->new($user{id});
	$secret_numbers{S12}->bxor($random_numbers{R12});

	# Order 2
	$secret_numbers{S21} = Math::BigInt->new($user{id});
	$secret_numbers{S21}->bxor($random_numbers{R21});

	$secret_numbers{S22} = Math::BigInt->new($user{id});
	$secret_numbers{S22}->bxor($random_numbers{R22});

	# Order 3
	$secret_numbers{S31} = Math::BigInt->new($user{id});
	$secret_numbers{S31}->bxor($random_numbers{R31});

	$secret_numbers{S32} = Math::BigInt->new($user{id});
	$secret_numbers{S32}->bxor($random_numbers{R32});
	
	my @keys = (
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

		# Blinding 
		
		my $key_name = "K".($i+1);
		my $k = $random_numbers{$key_name};
		my $blinding_factor = Math::BigInt->new($k);
		$blinding_factor->bmodpow($bank{e}, $bank{n});
		
		my @blinded_order = (
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
		
		push @blinded_orders, \@blinded_order;
	}
	
	write_json_file(\@blinded_orders, $order_output);
}
