# frozen_string_literal: true

return if RUBY_ENGINE == "jruby"
return unless defined?(Gem)

require "rubygems/commands/push_command"

Gem::Commands::PushCommand.prepend(Module.new do
  def send_push_request(name, args)
    puts "[ATTESTATION DEBUG] send_push_request called for #{name}"
    puts "[ATTESTATION DEBUG] attestations option: #{options[:attestations]&.any?}, host: #{@host}"
    return super if options[:attestations]&.any? || @host != "https://rubygems.org"

    begin
      puts "[ATTESTATION DEBUG] Attempting attestation-based push"
      send_push_request_with_attestation(name, args)
    rescue StandardError => e
      puts "[ATTESTATION DEBUG] Attestation failed with error: #{e.class} - #{e.message}"
      alert_warning "Failed to push with attestation, retrying without attestation.\n#{e.full_message}"
      super
    end
  end

  def send_push_request_with_attestation(name, args)
    puts "[ATTESTATION DEBUG] send_push_request_with_attestation called"
    attestation = attest!(name)
    puts "[ATTESTATION DEBUG] Attestation completed, bundle file: #{attestation}"
    if options[:attestations]
      puts "[ATTESTATION DEBUG] Adding attestation to options"
      options[:attestations] << attestation
      send_push_request(name, args)
    else
      puts "[ATTESTATION DEBUG] Sending push with attestation via multipart request"
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
    puts "[ATTESTATION DEBUG] attest! method called for #{name}"
    require "open3"

    # Install sigstore and sigstore-cli from the GitHub SHA
    puts "[ATTESTATION DEBUG] Installing sigstore from GitHub SHA"
    install_cmd = [
      Gem.ruby, "-S", "gem", "install",
      "--no-document",
      "git+https://github.com/sigstore/sigstore-ruby.git@ce93acf7fa7e26ba81ff21820848d7df2273a557"
    ]
    puts "[ATTESTATION DEBUG] Running: #{install_cmd.inspect}"
    out, st = Open3.capture2e(*install_cmd)
    puts "[ATTESTATION DEBUG] Install output:\n#{out}"
    raise Gem::Exception, "Failed to install sigstore from GitHub:\n\n#{out}" unless st.success?
    puts "[ATTESTATION DEBUG] Gem installation succeeded"

    bundle = "#{name}.sigstore.json"
    puts "[ATTESTATION DEBUG] Bundle output file will be: #{bundle}"

    env = defined?(Bundler.unbundled_env) ? Bundler.unbundled_env : ENV.to_h
    puts "[ATTESTATION DEBUG] Using unbundled env: #{defined?(Bundler.unbundled_env)}"

    cmd = [Gem.ruby, "-S", "gem", "exec", "sigstore-cli", "sign", name, "--bundle", bundle]
    puts "[ATTESTATION DEBUG] About to run command: #{cmd.inspect}"

    out, st = Open3.capture2e(
      env,
      *cmd,
      unsetenv_others: true
    )

    puts "[ATTESTATION DEBUG] Command exit status: #{st.exitstatus}"
    puts "[ATTESTATION DEBUG] Command output:\n#{out}"

    raise Gem::Exception, "Failed to sign gem:\n\n#{out}" unless st.success?

    puts "[ATTESTATION DEBUG] Attestation successful, returning bundle: #{bundle}"
    bundle
  end
end)
