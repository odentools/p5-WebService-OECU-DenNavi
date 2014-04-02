package WebService::OECU::DenNavi::Visitor;
use warnings;
use strict;
use Carp;
use utf8;

use version;
our $VERSION = qv('0.0.1');

use base qw/Class::Accessor/;
use Encode;
use LWP::UserAgent;
use HTTP::Headers;
use URI;
use Hash::AsObject;
use HTML::TreeBuilder;
use Data::Dumper;

my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
$year += 1900;
$mon += 1;

our %SEARCH_QUERY_PARAMS = (
	Page => 1,
	SortId => 0,
	IsAscendingOrder => 'True',
	DispNumber => 50,
	VisitorCompName => '',
	VisitorYear => $year,
	VisitorMonth => $mon,
	visitorGroup => '',
	VisitorPeriod => '0',
	IndustrialGroup => '',
	OccupationGroup => '',
	visitorInfoId => '',
);

# Accessors
__PACKAGE__->mk_accessors( qw/ iter / );

# Constructor
sub new {
	my ($class, $parent) = @_;
	my $self = bless({}, $class);
	$self->{parent} = $parent;
	return $self;
}

# Fetch a list of visitors
sub fetch_list {
	my ($s, %query) = @_;
	my $is_retry = $query{is_retry} || undef;

	foreach (keys %SEARCH_QUERY_PARAMS) {
		if (!exists $query{$_}) {
			$query{$_} = $SEARCH_QUERY_PARAMS{$_};
		}
	}

	# Request
	my $url = $s->_generate_post_url('TopMenu/VisitorInfoSearch');
	my $response = $s->{parent}->{ua}->post($url, 
		'Cookie' => 'ASP.NET_SessionId=' . $s->{parent}->{session_id},
		'Referer' => $s->{parent}->{baseurl} . 'TopMenu/VisitorInfoSearch',
		'Content-Type' => 'application/x-www-form-urlencoded',
		'Origin' => 'https://dennavi.osakac.ac.jp',
		'Content' => \%query,
	);

	if(! $response->is_success){
		die 'Fetch error: '.$response->as_string();
	} elsif (Encode::decode_utf8($response->title()) =~ /ログイン/ && !defined $is_retry) {
		# Retry
		$s->{parent}->login();
		$query{is_retry} = 1; 
		return $s->fetch_list(%query);
	}
	return $s->_parse_list_page($response->decoded_content());
}


# Fetch a detail of visitor
sub fetch_detail {
	my ($s, $visitor_info_id, $is_retry) = @_;

	# Request
	my $url = $s->_generate_post_url('TopMenu/VisitorInfoDetail');
	my $response = $s->{parent}->{ua}->post($url, 
		'Cookie' => 'ASP.NET_SessionId=' . $s->{parent}->{session_id},
		'Referer' => $s->{parent}->{baseurl} . 'TopMenu/VisitorInfoSearch',
		'Content-Type' => 'application/x-www-form-urlencoded',
		'Origin' => 'https://dennavi.osakac.ac.jp',
		'Content' => {
			'visitorInfoId' => $visitor_info_id,
		},
	);

	if(! $response->is_success){
		die 'Fetch error: '.$response->as_string();
	} elsif (Encode::decode_utf8($response->title()) =~ /ログイン/ && !defined $is_retry) {
		# Retry
		$s->{parent}->login();
		warn "Retrying...";
		return $s->fetch_detail($visitor_info_id, 1);
	}
	return $s->_parse_detail_page($response->decoded_content());
}

# Parse list page
sub _parse_list_page {
	my ($s, $html) = @_;
	my @arr = ();
	my $tree = HTML::TreeBuilder->new();
	$tree->parse($html);

	my @items =  $tree->look_down('id', 'raihouInfSrcTbl')->find('tr');
	foreach my $item (@items) {
		my $hash = {};
		my @columns = $item->find('td');
		if (defined $columns[0] && defined $columns[5]) {
			# Visit date
			$hash->{visited_at} = Encode::encode_utf8($columns[0]->as_text);
			# Type
			$hash->{type} = Encode::encode_utf8($columns[1]->as_text);
			# Industrial
			$hash->{industrial} = Encode::encode_utf8($columns[2]->as_text);
			# Occupation
			$hash->{occupation} = Encode::encode_utf8($columns[3]->as_text);
			# Name
			$hash->{name} = Encode::encode_utf8($columns[4]->as_text);
			# ID
			my $detail_tag = Encode::encode_utf8($columns[5]->as_HTML());
			#print "$detail_tag\n";
			if ($detail_tag =~ /(VI\-[\d]+\-[\d]+)/ ) {
				$hash->{id} = $1;
			}

			# Check
			if (!defined $hash->{name} || !defined $hash->{id}) {
				next;
			}

			push(@arr, $hash);
		}
	}
	return @arr;
}

# Parse detail page
sub _parse_detail_page {
	my ($s, $html) = @_;
	my @arr = ();
	my $tree = HTML::TreeBuilder->new();
	$tree->parse($html);
	my $hash = {};
	my @rows =  $tree->look_down('class', 'detailInfoBody')->find('tr');
	foreach my $row (@rows) {
		my @columns_th = $row->find('th');
		my @columns_td = $row->find('td');
		if (defined $columns_th[0] && defined $columns_td[0]) {
			my $name_raw = $columns_th[0]->as_text;
			my $value = Encode::encode_utf8($columns_td[0]->as_text);

			if ($name_raw eq '来訪日') {
				# Visit date
				$hash->{visited_at} = $value;
			} elsif ($name_raw eq '来訪企業名') {
				# Name
				$hash->{name} = $value;
			} elsif ($name_raw eq '来訪分類') {
				# Type
				$hash->{type} = $value;
			}
		}
	}

	@rows =  $tree->look_down('m:id', 'm_entryList')->find('td');
	foreach my $row (@rows) {
		if (defined $row) {
			my $value = Encode::encode_utf8($row->as_HTML('utf8'));
			$value =~ s/<br( | \/)>/\n\r/g;
			$value =~ s/<.*?>//g;
			$hash->{detail} = $value;
		}
	}

	# Check
	if (!defined $hash->{name}) {
		return undef;
	}
	
	return $hash;
}

# Generate a URL for the POST request
sub _generate_post_url {
	my ($s, $path) = @_;
	return $s->{parent}->{baseurl} . $path;
}

1;