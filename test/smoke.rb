# Boot an OmniAuth app with the CAS strategy on omniauth 2 / Rack 3 / Ruby 4 and
# drive the request phase. Proves the strategy loads and runs on omniauth 2
# (the gem was pinned to omniauth ~> 1.2, incompatible with Rack 3).
$stdout.sync = true
require 'logger'
require 'rack'
require 'rack/session'
require 'omniauth'
require 'omniauth-cas'

$failed = false
def check(label)
  yield
  puts "[ok] #{label}"
rescue => e
  puts "[FAIL] #{label}: #{e.class}: #{e.message}"
  puts e.backtrace.first(6).map { |l| "      #{l}" }
  $failed = true
end

puts "stack: ruby #{RUBY_VERSION} / omniauth #{Gem.loaded_specs['omniauth'].version.to_s} / rack #{Rack.release}"

OmniAuth.config.logger = Logger.new(IO::NULL)
OmniAuth.config.allowed_request_methods = [:get, :post]   # omniauth 2 defaults to POST-only
OmniAuth.config.request_validation_phase = nil            # skip CSRF token for the smoke

app = Rack::Builder.new do
  use Rack::Session::Cookie, secret: 'x' * 64, same_site: true
  use OmniAuth::Builder do
    provider :cas, host: 'cas.example.org', ssl: true
  end
  run ->(_env) { [404, { 'content-type' => 'text/plain' }, ['not found']] }
end.to_app

check "the CAS strategy is registered on omniauth 2" do
  raise "not loaded" unless defined?(OmniAuth::Strategies::CAS)
  raise "omniauth not 2.x" unless Gem.loaded_specs['omniauth'].version.to_s.split('.').first.to_i >= 2
end

check "request phase redirects (302) to the CAS login URL" do
  # CAS appends the post-auth return URL as the `url` param and validates it
  # (anti-phishing); same host as the callback, so it's accepted.
  env = Rack::MockRequest.env_for('https://app.test/auth/cas?url=https://app.test/dashboard', method: 'GET')
  status, headers, _body = app.call(env)
  raise "status #{status}" unless status == 302
  loc = headers['location'] || headers['Location']
  raise "bad Location: #{loc.inspect}" unless loc &&
    loc.include?('cas.example.org') && loc.include?('/login') && loc.include?('service=')
end

if $failed
  puts "\nSMOKE FAILED"
  exit 1
else
  puts "\nSMOKE OK — omniauth-cas runs on omniauth #{Gem.loaded_specs['omniauth'].version.to_s} / Ruby #{RUBY_VERSION}"
end
