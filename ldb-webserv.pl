#!/usr/bin/perl
#
# @author: pj4dev.mit@gmail.com
#
use warnings;
use Tie::LevelDB;
use IO::Socket;
use JSON;
use MIME::Base64;
use Data::Dumper;

$config_file = "ldb-webserv.conf";

sub readConfig {
    my $config_file = shift @_;
    open CONF, "<", $config_file;
    my $json_config;
    while(<CONF>) {
      chomp;
      $json_config .= $_;
    }
    close CONF;
    return %{decode_json $json_config};
}

sub jsonPrepareReturn {
    my ($nkey, $key, $nvalue, $value) = @_;
    return "{
      \"$nkey\" : \"$key\",
      \"$nvalue\" : \"$value\"
}";
}

sub checkAuth {
    my $configRef = shift @_;
    my %config = %{$configRef};
    my $username = shift @_;
    my $password = shift @_;
    return ($config{Username} eq $username and $config{Password} eq $password)? 1: 0;
}

%config = readConfig($config_file);
$authen = (defined $config{Username} and $config{Username} !~ /^$/)? 1: 0;
die "Configuration file error (not specify DBName).\n" unless ($config{DBName});
die "Configuration file error (not specify Port).\n" unless ($config{Port});
$verbose = 0;
if (@ARGV > 0) {
  if ($ARGV[0] =~ /^(-v|--verbose)$/) {
    $verbose = 1;
  }
  elsif ($ARGV[0] =~ /^(-h|--help)$/ or $ARGV[0] !~ /^$/) {
    print "Usage: $0 [-v|--verbose]\n";
    exit 1;
  }
}

$server = IO::Socket::INET->new(LocalPort => $config{Port}, ReuseAddr => 1, Listen => SOMAXCONN) or die $!;
while ($conn = $server->accept()) {
  if (fork() != 0){
    close ($conn);
    next;
  }
  my %request = ();
  while (<$conn>) {
   chomp;
   # read HTTP request header
   if (/\s*(\w+)\s*([^\s]+)\s*HTTP\/(\d.\d)/) {
       $request{METHOD} = uc $1;
       $request{URL} = $2;
       $request{HTTP_VERSION} = $3;
   }
   # read HTTP header parameters
   elsif (/:/) {
       (my $type, my $val) = split /:/, $_, 2;
       $type =~ s/^\s+//;
       foreach ($type, $val) {
               s/^\s+//;
               s/\s+$//;
       }
       $request{uc $type} = $val;
   }
   # read HTTP request body
   else {
       read($conn, $request{CONTENT}, $request{'CONTENT-LENGTH'}) if defined $request{'CONTENT-LENGTH'};
       last;
   }
  }
  my %content = %{decode_json $request{CONTENT}} if (defined $request{CONTENT});
  my $return_json = undef;
  # check valid url (start with /api/...)
  if ($request{URL} !~ /^\/api\b/) {
    print "[LOG] wrong request URL\n" if ($verbose);
    $return_json = "{}";
    goto RESPONSE;
  }
  # check valid username and password
  if ($authen) {
    my $type = $credential = $username = $password = '';
    ($type, $credential) = split / /, $request{AUTHORIZATION} if (defined $request{AUTHORIZATION});
    ($username, $password) = split /:/, decode_base64 $credential;
    if (not checkAuth \%config, $username, $password) {
      print "[LOG] authentication failed\n" if ($verbose);
      $return_json = "{}";
      goto RESPONSE;
    }
  }
  # check a request type
  if ($request{METHOD} eq "GET") {
    my @elements = split '/', $request{URL};
    my $key = $elements[2];
    my $db = new Tie::LevelDB::DB($config{DBName});
    my $value = $db->Get($key) || '';
    print "[LOG] retrieve $key -> $value\n" if ($verbose);
    $return_json = jsonPrepareReturn(
                  "key",
                  $key,
                  "value",
                  $value
    );
  } elsif ($request{METHOD} eq "POST") {
    if (defined $content{key} and defined $content{value}) {
      my $db = new Tie::LevelDB::DB($config{DBName});
      $db->Put($content{key}, $content{value});
      print "[LOG] create or update $content{key} -> $content{value}\n" if ($verbose);
      $return_json = jsonPrepareReturn(
                    "success",
                    "1",
                    "err_msg",
                    ""
      );
    } else {
      print "[LOG] create or update - invalid parameters\n" if ($verbose);
      $return_json = jsonPrepareReturn(
                  "success",
                  "0",
                  "err_msg",
                  "invalid parameters"
      );
    }
  } elsif ($request{METHOD} eq "DELETE") {
    my @elements = split '/', $request{URL};
    my $key = $elements[2];
    my $db = new Tie::LevelDB::DB($config{DBName});
    my $res = $db->Delete($key);
    print "[LOG] delete $key\n" if ($verbose);
    if (not $res) {
      $return_json = jsonPrepareReturn(
                    "success",
                    "1",
                    "err_msg",
                    ""
      );
    } else {
      $return_json = jsonPrepareReturn(
                    "success",
                    "0",
                    "err_msg",
                    "no item found"
      );
    }
  } elsif ($request{METHOD} eq "PUT") {
    if (defined $content{batch}) {
      my $db = new Tie::LevelDB::DB($config{DBName});
      my $batch = new Tie::LevelDB::WriteBatch;
      my @commands = @{$content{batch}};
      print "[LOG] execute batch @commands\n" if ($verbose);
      my $error = 0;
      foreach $command (@commands) {
        my @params = split / /, $command;
        if (lc $params[0] eq "delete") {
          if (defined $params[1]) {
            $batch->Delete($params[1]);
          } else {
            $error = 1;
            last;
          }
        } elsif (lc $params[0] eq "put") {
          if (defined $params[1] and defined $params[2]) {
            $batch->Put($params[1], $params[2]);
          } else {
            $error = 1;
            last;
          }
        } else {
          $error = 1;
          last;
        }
      }
      if ($error) {
        $return_json = jsonPrepareReturn(
                      "success",
                      "0",
                      "err_msg",
                      "invalid commands"
        );
      } else {
        $db->Write($batch);
        $return_json = jsonPrepareReturn(
                      "success",
                      "1",
                      "err_msg",
                      ""
        );
      }
    } else {
      $return_json = jsonPrepareReturn(
                  "success",
                  "0",
                  "err_msg",
                  "invalid parameters"
      );
    }
  } else {
    $return_json = "{}";
  }

RESPONSE:
  print $conn "HTTP/1.1 200 OK\n";
  print $conn "Content-Type: application/json\n\n";
  print $conn $return_json;
  close $conn;
  exit 0;
}
