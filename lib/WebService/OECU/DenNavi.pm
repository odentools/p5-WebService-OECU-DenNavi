package WebService::OECU::DenNavi;
#############################################
# OECU DENNavi Client module
# (C) OdenTools Project - 2014.
#############################################
use warnings;
use strict;
use Carp;
use utf8;

use version;
our $VERSION = qv('0.0.1');

use base qw/Class::Accessor/;
use LWP::UserAgent;
use HTTP::Request::Common;
use URI;
use Hash::AsObject;

use WebService::OECU::DenNavi::Corporate;

# Accessors
__PACKAGE__->mk_accessors( qw/ iter / );

# Constructor
sub new {
	my ($class, %param) = @_;
	my $self = bless({}, $class);

	# Parameter - Base URL
	if(defined($param{baseurl})){
		$self->{baseurl} = $param{baseurl};
		delete $param{baseurl};
	}else{
		$self->{baseurl} = 'https://dennavi.osakac.ac.jp/GSWeb/';
	}

	# Parameter - Automatic next page fetch 
	if(defined($param{disable_nextpage_fetch}) && $param{disable_nextpage_fetch}){
		$self->{nextpage_fetch} = 0;
		delete $param{disable_nextpage_fetch};
	}else{
		$self->{nextpage_fetch} = 1;
	}

	# Parameter - Username
	$self->{username} = $param{username} || undef;
	delete $param{username};
	# Parameter - Password
	$self->{password} = $param{password} || undef;
	delete $param{password};
	# Parameter - SessionID
	$self->{session_id} = $param{session_id} || undef;
	delete $param{session_id};

	# UA-Parameter - Timeout
	$param{timeout} =  $param{timeout} || 10;

	# UA-Parameter - UserAgent string
	$param{agent} =  $param{agent} || __PACKAGE__.'/'.$VERSION;

	# ----------

	# Prepare a LWP::UA instance
	$self->{ua} = LWP::UserAgent->new(%param);

	# Initialize sub objects
	$self->{corporate} = WebService::OECU::DenNavi::Corporate->new($self);
	
	# ----------

	return $self;
}

# Login
sub login {
	my ($s, $username, $password) = @_;
	if (defined $username && defined $password) {
		$s->{username} = $username;
		$s->{password} = $password;
	}
	
	# Login
	if (defined $s->{username} && defined $s->{password}) {
		# Request
		my $url = $s->_generate_post_url('Login/Login');
		my $req = HTTP::Request->new(POST => $url);
		$req->referer($s->{baseurl});
		$req->content_type('application/x-www-form-urlencoded');
		my $content = "userId=".$s->{username}."&password=".$s->{password}."&Submit=ログイン";
		utf8::encode($content);
		$req->content($content);
		my $response = $s->{ua}->request($req);
		if($response->code() == 302 && $response->header("Set-Cookie") =~ /ASP\.NET\_SessionId=(\w+).*/){
			# Login successful
			$s->{session_id} = $1;
			return $s->{session_id};
		}
		die "Login-error:" . $response->as_string();
	}
	die "Username or password is null";
}

# Get a session-id
sub get_session_id {
	return shift->{session_id};
}

# Get a client for corporate
sub corporate {
	return shift->{corporate};
}

# Generate a URL for the POST request
sub _generate_post_url {
	my ($s, $path) = @_;
	return $s->{baseurl} . $path;
}

1;