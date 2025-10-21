# frozen_string_literal: true

return if RUBY_ENGINE == "jruby"
return unless defined?(Gem)

require "rubygems/commands/push_command"

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
    require "tmpdir"
    require "fileutils"

    # Clone sigstore-ruby from GitHub at the specified SHA
    tmpdir = Dir.mktmpdir("sigstore-ruby-")
    clone_cmd = ["git", "clone", "https://github.com/sigstore/sigstore-ruby.git", tmpdir]
    out, st = Open3.capture2e(*clone_cmd)
    raise Gem::Exception, "Failed to clone sigstore-ruby:\n\n#{out}" unless st.success?

    # Checkout the specific SHA
    checkout_cmd = ["git", "-C", tmpdir, "checkout", "ce93acf7fa7e26ba81ff21820848d7df2273a557"]
    out, st = Open3.capture2e(*checkout_cmd)
    raise Gem::Exception, "Failed to checkout SHA:\n\n#{out}" unless st.success?

    # Install dependencies with bundler
    bundle_install_cmd = ["bundle", "install", "--quiet"]
    out, st = Open3.capture2e(*bundle_install_cmd, chdir: tmpdir)
    raise Gem::Exception, "Failed to install sigstore dependencies:\n\n#{out}" unless st.success?

    bundle = "#{name}.sigstore.json"

    # Run sigstore-cli using bundle exec
    cli_cmd = ["bundle", "exec", "bin/sigstore-cli", "sign", name, "--bundle", bundle]
    out, st = Open3.capture2e(*cli_cmd, chdir: tmpdir)
    raise Gem::Exception, "Failed to sign gem:\n\n#{out}" unless st.success?

    bundle
  ensure
    # Clean up the temporary directory
    if defined?(tmpdir) && tmpdir && File.directory?(tmpdir)
      FileUtils.rm_rf(tmpdir) rescue nil
    end
  end
end)
