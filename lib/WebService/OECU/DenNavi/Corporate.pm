package WebService::OECU::DenNavi::Corporate;
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

our %SEARCH_QUERY_PARAMS = (
	Page => 0,
	SortId => 0,
	IsAscendingOrder => 'True',
	DispNumber => 50,
	CorpoNum => '',
	CorpoName => '',
	CorpoActivity => '',
	JobExistence => 0,
	OBExistence => 0,
	CorpoEstablishStart => '',
	CorpoEstablishEnd => '',
	CorpoCapitalStart => '',
	CorpoCapitalEnd => '',
	CorpoemployeesStart => '',
	CorpoemployeesEnd => '',
	CorpoAddress => '',
	#IndustrialsSection => '',
	#SelectStockType => '',
	#CorpoParentName => '',
	#CorpoGroup => 0,
	#GroupCityIDList => 0,
	#CorporateCity => 0,
	#formCommon => '',
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

# Fetch a list of corporates
sub fetch_list {
	my ($s, %query) = @_;
	my $is_retry = $query{is_retry} || undef;

	foreach (keys %SEARCH_QUERY_PARAMS) {
		if (!exists $query{$_}) {
			$query{$_} = $SEARCH_QUERY_PARAMS{$_};
		}
	}

	# Request
	my $url = $s->_generate_post_url('Search/SearchCorporateList');
	my $response = $s->{parent}->{ua}->post($url, 
		'Cookie' => 'ASP.NET_SessionId=' . $s->{parent}->{session_id},
		'Referer' => $s->{parent}->{baseurl} . 'Search/SearchCorporate',
		'Content-Type' => 'application/x-www-form-urlencoded',
		'Origin' => 'https://dennavi.osakac.ac.jp',
		'Content' => \%query,
	);

	if(! $response->is_success){
		die 'Fetch error: '.$response->as_string();
	} elsif ($response->title() =~ /ログイン/ && !defined $is_retry) {
		# Retry
		warn $s->{parent}->login();
		$query{is_retry} = 1; 
		return $s->fetch_list(%query);
	}

	return $s->_parse_list_page($response->decoded_content());
}

# Parse list page
sub _parse_list_page {
	my ($s, $html) = @_;
	my @arr = ();
	my $tree = HTML::TreeBuilder->new();
	$tree->parse($html);

	my @items =  $tree->look_down('id', 'scrolltable')->find('tr');
	foreach my $item (@items) {
		my $hash = {};
		my @columns = $item->find('td');
		if (defined $columns[0] && defined $columns[8]) {
			# Name
			$hash->{name} = Encode::encode_utf8($columns[0]->as_text);
			# Pref
			$hash->{prefecture} = Encode::encode_utf8($columns[4]->as_text);
			# Industrial
			$hash->{industrial} = Encode::encode_utf8($columns[5]->as_text);
			# Updated
			$hash->{updated} = Encode::encode_utf8($columns[6]->as_text);
			# ID
			my $detail_tag = Encode::encode_utf8($columns[8]->as_HTML());
			if ($detail_tag =~ /GSWeb\/Detail\/CorporateDetail\/([0-9A-z-]+)/ ) {
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

# Generate a URL for the POST request
sub _generate_post_url {
	my ($s, $path) = @_;
	return $s->{parent}->{baseurl} . $path;
}

1;