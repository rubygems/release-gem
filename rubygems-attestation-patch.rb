# frozen_string_literal: true

return if RUBY_ENGINE == "jruby"
return unless defined?(Gem)

require "rubygems/commands/push_command"

# RubyGems 4.1.0.dev signs on its own, and its #send_push_request delegates to
# a #send_push_request_with_attestation of its own.  Prepending a method of
# that name in front of it makes the two call each other forever: the patch
# delegates up with `super`, RubyGems delegates back down by name, and every
# lap signs the gem again.  Leave the newer RubyGems to it.
if Gem::Commands::PushCommand.private_method_defined?(:send_push_request_with_attestation) ||
   Gem::Commands::PushCommand.method_defined?(:send_push_request_with_attestation)
  return
end

Gem::Commands::PushCommand.prepend(Module.new do
  def send_push_request(name, args)
    return super if options[:attestations]&.any? || @host != "https://rubygems.org"

    begin
      send_push_request_with_attestation(name, args)
    rescue StandardError => e
      alert_warning "Failed to push with attestation, retrying without attestation.\n#{e.full_message}"
      super
    end
  end

  def send_push_request_with_attestation(name, args)
    attestation = attest!(name)
    if options[:attestations]
      options[:attestations] << attestation
      send_push_request(name, args)
    else
      rubygems_api_request(*args, scope: get_push_scope) do |request|
        request.set_form([
                           ["gem", Gem.read_binary(name), { filename: name, content_type: "application/octet-stream" }],
                           ["attestations", "[#{Gem.read_binary(attestation)}]", { content_type: "application/json" }]
                         ], "multipart/form-data")
        request.add_field "Authorization", api_key
      end
    end
  end

  def attest!(name)
    require "open3"
    bundle = "#{name}.sigstore.json"
    env = defined?(Bundler.unbundled_env) ? Bundler.unbundled_env : ENV.to_h
    out, st = Open3.capture2e(
      env,
      Gem.ruby, "-S", "gem", "exec",
      "sigstore-cli:0.2.3", "sign", name, "--bundle", bundle,
      unsetenv_others: true
    )
    raise Gem::Exception, "Failed to sign gem:\n\n#{out}" unless st.success?

    bundle
  end
end)
