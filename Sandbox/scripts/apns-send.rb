#!/usr/bin/env ruby
# Sends one alert notification through APNs with token-based (.p8) authentication.
# Usage: apns-send.rb <AuthKey_XXXX.p8> <key id> <team id> <bundle id> <device token> [sandbox|production]
require 'openssl'
require 'base64'
require 'json'

p8, key_id, team_id, bundle_id, device_token, env = ARGV
abort "usage: #{$0} <p8> <key id> <team id> <bundle id> <device token> [sandbox|production]" unless device_token
host = env == 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com'

b64 = ->(s) { Base64.urlsafe_encode64(s, padding: false) }
signing_input = [
  b64.({ alg: 'ES256', kid: key_id }.to_json),
  b64.({ iss: team_id, iat: Time.now.to_i }.to_json)
].join('.')

# OpenSSL returns a DER signature; a JWT expects the raw 32-byte r and s concatenated
der = OpenSSL::PKey.read(File.read(p8)).sign(OpenSSL::Digest.new('SHA256'), signing_input)
r, s = OpenSSL::ASN1.decode(der).value.map { |i| i.value.to_s(2).rjust(32, "\x00".b) }
jwt = "#{signing_input}.#{b64.(r + s)}"

payload = {
  aps: {
    alert: { title: 'Valider la connexion', body: 'Une demande de connexion attend votre validation' },
    sound: 'default',
    'interruption-level': 'time-sensitive'
  },
  auth_req_id: 'etude-CA-5813'
}.to_json

exec 'curl', '-sS', '--http2', '-w', "\nHTTP %{http_code}\n", '-D', '-',
     '-H', "authorization: bearer #{jwt}",
     '-H', "apns-topic: #{bundle_id}",
     '-H', 'apns-push-type: alert',
     '-H', 'apns-priority: 10',
     '-H', 'apns-expiration: 0',
     '-d', payload,
     "https://#{host}/3/device/#{device_token}"
