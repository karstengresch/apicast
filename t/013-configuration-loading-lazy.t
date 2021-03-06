use Test::Nginx::Socket 'no_plan';
use Cwd qw(cwd);

my $pwd = cwd();
my $apicast = $ENV{TEST_NGINX_APICAST_PATH} || "$pwd/apicast";

$ENV{TEST_NGINX_LUA_PATH} = "$apicast/src/?.lua;;";
$ENV{TEST_NGINX_HTTP_CONFIG} = "$apicast/http.d/init.conf";
$ENV{TEST_NGINX_UPSTREAM_CONFIG} = "$apicast/http.d/upstream.conf";
$ENV{TEST_NGINX_APICAST_CONFIG} = "$apicast/conf.d/apicast.conf";
$ENV{TEST_NGINX_BACKEND_CONFIG} = "$apicast/conf.d/backend.conf";
$ENV{TEST_NGINX_APICAST_PATH} = $apicast;
$ENV{APICAST_CONFIGURATION_LOADER} = 'lazy';

env_to_nginx(
    'APICAST_CONFIGURATION_LOADER',
    'TEST_NGINX_APICAST_PATH',
    'THREESCALE_CONFIG_FILE',
    'THREESCALE_PORTAL_ENDPOINT'
);

log_level('debug');
repeat_each(1);
no_root_location();
run_tests();

__DATA__

=== TEST 1: load empty configuration
should just say service is not found
--- main_config
env THREESCALE_PORTAL_ENDPOINT=http://127.0.0.1:$TEST_NGINX_SERVER_PORT;
--- http_config
  include $TEST_NGINX_HTTP_CONFIG;
  lua_package_path "$TEST_NGINX_LUA_PATH";
--- config
  include $TEST_NGINX_APICAST_CONFIG;

  location = /admin/api/nginx/spec.json {
   echo "{}";
  }
--- request
GET /t
--- error_code: 404
--- error_log
service not found for host localhost

=== TEST 2: load invalid configuration
should fail with server error
--- main_config
env THREESCALE_PORTAL_ENDPOINT=http://127.0.0.1:$TEST_NGINX_SERVER_PORT;
--- http_config
  include $TEST_NGINX_HTTP_CONFIG;
  lua_package_path "$TEST_NGINX_LUA_PATH";
--- config
  include $TEST_NGINX_APICAST_CONFIG;

  location = /admin/api/nginx/spec.json {
    echo "";
  }
--- request
GET /t
--- error_code: 404

=== TEST 3: load valid configuration
should correctly route the request
--- main_config
env THREESCALE_PORTAL_ENDPOINT=http://127.0.0.1:$TEST_NGINX_SERVER_PORT;
--- http_config
  include $TEST_NGINX_HTTP_CONFIG;
  include $TEST_NGINX_UPSTREAM_CONFIG;
  lua_package_path "$TEST_NGINX_LUA_PATH";
--- config
  include $TEST_NGINX_APICAST_CONFIG;
  include $TEST_NGINX_BACKEND_CONFIG;

  location = /admin/api/nginx/spec.json {
    try_files /config.json =404;
  }

  location /api/ {
    echo "all ok";
  }
--- request
GET /t?user_key=fake
--- error_code: 200
--- user_files eval
[
  [ 'config.json', qq|
  {
    "services": [{
      "id": 1,
      "backend_version": 1,
      "proxy": {
        "api_backend": "http://127.0.0.1:$ENV{TEST_NGINX_SERVER_PORT}/api/",
        "backend": {
          "endpoint": "http://127.0.0.1:$ENV{TEST_NGINX_SERVER_PORT}"
        },
        "proxy_rules": [
          { "pattern": "/t", "http_method": "GET", "metric_system_name": "test" }
        ]
      }
    }]
  }
  | ]
]

