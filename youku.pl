use MIME::Base64;
use LWP::UserAgent;
use JSON;
use URI::Escape;
use Time::HiRes;
use HTTP::Cookies;

sub rc4_encode {
	my($a, $c) = @_;
	my($f, $h, $q, $r);
	my @b = (0..255);
	for ($h = 0; $h < 256; ++ $h) {
		$f = ($f +	$b[$h] + ord(substr($a, $h % length($a), 1))) % 256;
		($b[$f], $b[$h]) = ($b[$h], $b[$f]);
	}
	$f = $h = 0;
	for ($q = 0; $q < length($c); ++ $q) {
		$h = ($h + 1) % 256;
		$f = ($f + $b[$h]) % 256;
		($b[$f], $b[$h]) = ($b[$h], $b[$f]);
		$r .= chr(ord(substr($c, $q, 1)) ^ $b[($b[$h] + $b[$f]) % 256]);
	}
	return $r;
}

sub rand_char {
	$n = $_[0];
	my $res;
	while ($n --) {
		if (int(rand(2))) {
			$res .= chr(ord('a') + int(rand(26)));
		} else {
			$res .= chr(ord('A') + int(rand(26)));
		}
	}
	return $res;
}

sub get_token_sid {
	my $en_str = $_[0];
	$en_str = decode_base64($en_str);
	my $t = rc4_encode('becaf9be', $en_str);
	my ($sid, $token) = split /_/, $t;
	return ($token, $sid);
}

sub get_ep {
	my($sid, $fileid, $token) = @_;
	my $w = join '_', $sid, $fileid, $token;
	$ep = encode_base64(rc4_encode('bf7e5f01', $w), '');
	return $ep
}

sub get_vid {
	$_[0] =~ m{(?:http://)?v.youku.com/v_show/id_(.+)\.html};
	return $1;
}

%hd = (
	'3gp' => '0',
	'3gphd' => '1',
	'flv' => '0',
	'flvhd' => '0',
	'mp4' => '1',
	'mp4hd' => '1',
	'mp4hd2' => '1',
	'mp4hd3' => '1',
	'hd2' => '2',
	'hd3' => '3',
);

%ext = (
	'3gp' => 'flv',
	'3gphd' => 'mp4',
	'flv' => 'flv',
	'flvhd' => 'flv',
	'mp4' => 'mp4',
	'mp4hd' => 'mp4',
	'mp4hd2' => 'flv',
	'mp4hd3' => 'flv',
	'hd2' => 'flv',
	'hd3' => 'flv',
);

die "Usage: $0 URI
eg: $0 http://v.youku.com/v_show/id_XNDk0MzkyNDA=.html
" unless $ARGV[0];
$vid = get_vid($ARGV[0]);
$ua = LWP::UserAgent->new( agent => 'Mozilla/5.0' );
$cookie_jar = HTTP::Cookies->new;
$cookie_jar->set_cookie(0, '__ysuid', int(Time::HiRes::time * 1000) . rand_char(3), '/', 'youku.com');
$ua->cookie_jar($cookie_jar);
$res = $ua->get("http://play.youku.com/play/get.json?vid=$vid&ct=12", referer => "http://play.youku.com/play/get.json?vid=$vid&ct=12");
$json = decode_json($res->content);
($token, $sid) = get_token_sid($json->{data}{security}{encrypt_string});
$oip = $json->{data}{security}{ip};
#$filename = $json->{data}{video}{title};
$filename = 'output';

for my $stream (@{$json->{data}{stream}}) {
	my $format = $stream->{stream_type};
	$addr{$format} = [];
	my $n = 0;
	for my $seg (@{$stream->{segs}}) {
		my ($fileid, $key) = @{$seg}{ qw/fileid key/ };
		$ep = get_ep($sid, $fileid, $token);
		$res = $ua->get("http://k.youku.com/player/getFlvPath/sid/$sid" . "_00/st/$ext{$format}/fileid/$fileid?K=$key&hd=$hd{$format}&myp=0&ypp=0&ctype=12&ev=1&token=$token&oip=$oip&ep=" . uri_escape($ep));
		open FOUT, '>', "$filename-$n". ".$ext{$format}";
		binmode FOUT;
		print FOUT $res->content;
		close FOUT;
		++ $n;
	}
}



