# frozen_string_literal: true

# Waits until RubyGems.org serves each given .gem file on the endpoints that
# `gem install` and `bundle install` read. Only public HTTP endpoints are used,
# so Bundler releases cannot break it.

require "net/http"
require "rubygems/package"

$stdout.sync = true
deadline = Time.now + 300

pending = ARGV.flat_map do |path|
  spec = Gem::Package.new(path).spec
  entry = spec.platform == Gem::Platform::RUBY ? spec.version.to_s : "#{spec.version}-#{spec.platform}"
  [
    [URI("https://index.rubygems.org/info/#{spec.name}"), /^#{Regexp.escape(entry)} /],
    [URI("https://rubygems.org/quick/Marshal.4.8/#{spec.full_name}.gemspec.rz"), nil],
    [URI("https://rubygems.org/gems/#{spec.full_name}.gem"), nil],
  ]
end

loop do
  responses = {}
  pending.reject! do |uri, pattern|
    response = responses[uri] ||=
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) do |http|
        pattern ? http.get(uri.path) : http.head(uri.path)
      end
    found = response.is_a?(Net::HTTPSuccess) && (pattern.nil? || pattern.match?(response.body))
    puts "found #{uri}" if found
    found
  rescue StandardError => e
    warn "#{uri}: #{e.class}: #{e.message}"
    false
  end
  break if pending.empty?

  if Time.now > deadline
    pending.each { |uri, _| warn "missing #{uri}" }
    abort "Timed out waiting for the release to propagate"
  end
  sleep 5
end
