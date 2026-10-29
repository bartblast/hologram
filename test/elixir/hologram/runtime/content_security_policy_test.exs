defmodule Hologram.Runtime.ContentSecurityPolicyTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Runtime.ContentSecurityPolicy

  @default_directives [
    base_uri: [:none],
    form_action: [:self],
    frame_ancestors: [:self],
    object_src: [:none],
    script_src: [:nonce, :strict_dynamic, :unsafe_inline, "https:"]
  ]

  setup do
    put_hologram_config(:content_security_policy, [])
  end

  @no_trusted_types_policy_message "config :hologram, :content_security_policy describes a policy no Hologram page could work under: :trusted_types allows no Trusted Types policy, Hologram's own among them, so list the policies the app creates, or \"*\" for every one"

  @source_message "but a source is visible ASCII without a semicolon or a comma, and not empty"

  defp put_config(config) do
    put_hologram_config(:content_security_policy, config)
  end

  defp unbootable_scripts_message(name) do
    "config :hologram, :content_security_policy describes a policy no Hologram page could work " <>
      "under: #{inspect(name)}, the directive governing script elements, names no :nonce, and " <>
      "allows the inline shell script through :unsafe_inline together with :self or a source " <>
      "the runtime is served from only without :strict_dynamic and without a hash, which make " <>
      "browsers ignore :unsafe_inline"
  end

  describe "directives/0" do
    test "the defaults, with no config" do
      assert directives() == @default_directives
    end

    test "a directive the config gives replaces the default for it" do
      put_config(form_action: [:self, "https://checkout.stripe.com"])

      assert directives()[:form_action] == [:self, "https://checkout.stripe.com"]
    end

    test "a directive the config adds joins the defaults, sorted by name" do
      put_config(img_src: [:self, "data:"])

      assert Keyword.keys(directives()) == [
               :base_uri,
               :form_action,
               :frame_ancestors,
               :img_src,
               :object_src,
               :script_src
             ]
    end

    test "a directive set to false is removed, the others kept" do
      put_config(frame_ancestors: false)

      assert directives() == Keyword.delete(@default_directives, :frame_ancestors)
    end

    test "a switch directive set to true joins the defaults" do
      put_config(upgrade_insecure_requests: true)

      assert directives() == [
               base_uri: [:none],
               form_action: [:self],
               frame_ancestors: [:self],
               object_src: [:none],
               script_src: [:nonce, :strict_dynamic, :unsafe_inline, "https:"],
               upgrade_insecure_requests: true
             ]
    end

    test "a switch directive set to false is left out" do
      put_config(upgrade_insecure_requests: false)

      assert directives() == @default_directives
    end

    test "no policy when the config is false" do
      put_config(false)

      assert directives() == nil
    end

    test "Hologram's Trusted Types policy added to the names a trusted_types directive allows" do
      put_config(require_trusted_types_for: [:script], trusted_types: ["default"])

      assert directives()[:trusted_types] == ["hologram", "default"]
    end

    test "Hologram's Trusted Types policy not added twice" do
      put_config(trusted_types: ["default", "hologram"])

      assert directives()[:trusted_types] == ["default", "hologram"]
    end

    test "no trusted_types directive added when the config removes it" do
      put_config(require_trusted_types_for: [:script], trusted_types: false)

      refute Keyword.has_key?(directives(), :trusted_types)
    end

    # Without the directive any policy name is allowed, and adding one would forbid the others.
    test "no trusted_types directive added when the config gives none" do
      put_config(require_trusted_types_for: [:script])

      refute Keyword.has_key?(directives(), :trusted_types)
    end

    test "no policy when the config removes every directive" do
      put_config(
        base_uri: false,
        form_action: false,
        frame_ancestors: false,
        object_src: false,
        script_src: false
      )

      assert directives() == nil
    end
  end

  describe "generate_nonce/0" do
    test "is 16 random bytes in base64" do
      nonce = generate_nonce()

      assert String.length(nonce) == 24
      assert byte_size(Base.decode64!(nonce)) == 16
    end

    test "differs between calls" do
      assert generate_nonce() != generate_nonce()
    end
  end

  describe "header_value/2" do
    test "the defaults, with the nonce" do
      assert header_value(@default_directives, "R4nd0m") ==
               "base-uri 'none'; form-action 'self'; frame-ancestors 'self'; object-src 'none'; " <>
                 "script-src 'nonce-R4nd0m' 'strict-dynamic' 'unsafe-inline' https:"
    end

    test "a keyword atom, quoted with hyphens" do
      assert header_value([script_src: [:wasm_unsafe_eval]], "R4nd0m") ==
               "script-src 'wasm-unsafe-eval'"
    end

    test "the nonce, in every directive naming it" do
      assert header_value([script_src: [:nonce], style_src: [:self, :nonce]], "R4nd0m") ==
               "script-src 'nonce-R4nd0m'; style-src 'self' 'nonce-R4nd0m'"
    end

    test "a string, as it is" do
      assert header_value([img_src: ["https://images.example.com", "data:"]], "R4nd0m") ==
               "img-src https://images.example.com data:"
    end

    test "a hash tuple, as a hash source" do
      assert header_value([style_src: [{:sha256, "YWJj"}]], "R4nd0m") ==
               "style-src 'sha256-YWJj'"
    end

    test "Trusted Types enforced, with Hologram's policy beside the app's" do
      put_config(
        require_trusted_types_for: [:script],
        trusted_types: ["default", :allow_duplicates]
      )

      assert header_value(directives(), "R4nd0m") ==
               "base-uri 'none'; form-action 'self'; frame-ancestors 'self'; object-src 'none'; " <>
                 "require-trusted-types-for 'script'; " <>
                 "script-src 'nonce-R4nd0m' 'strict-dynamic' 'unsafe-inline' https:; " <>
                 "trusted-types hologram default 'allow-duplicates'"
    end

    test "require-trusted-types-for, with its script keyword" do
      assert header_value([require_trusted_types_for: [:script]], "R4nd0m") ==
               "require-trusted-types-for 'script'"
    end

    test "a switch directive set to true, as its bare name" do
      assert header_value([upgrade_insecure_requests: true], "R4nd0m") ==
               "upgrade-insecure-requests"
    end

    test "an empty source list, as the bare directive name" do
      assert header_value([img_src: []], "R4nd0m") == "img-src"
    end
  end

  describe "nonced_elements/1" do
    test "script elements under the defaults" do
      assert nonced_elements(directives()) == ["script"]
    end

    test "link and style elements too when style_src names the nonce" do
      put_config(style_src: [:self, :nonce])

      assert nonced_elements(directives()) == ["link", "script", "style"]
    end

    test "follows script_src_elem over script_src" do
      put_config(script_src_elem: [:self, :unsafe_inline])

      assert nonced_elements(directives()) == []
    end

    test "follows style_src_elem over style_src" do
      put_config(style_src: [:self], style_src_elem: [:nonce])

      assert nonced_elements(directives()) == ["link", "script", "style"]
    end

    test "follows default_src when script_src is removed" do
      put_config(default_src: [:self, :nonce], script_src: false)

      assert nonced_elements(directives()) == ["link", "script", "style"]
    end

    test "none when the policy is off" do
      put_config(false)

      assert nonced_elements(directives()) == []
    end
  end

  describe "validate_config!/0" do
    test "passes for no config" do
      assert validate_config!() == :ok
    end

    test "passes for false" do
      put_config(false)

      assert validate_config!() == :ok
    end

    test "passes for a config using every kind of value" do
      put_config(
        frame_ancestors: false,
        img_src: [:self, "data:"],
        sandbox: ["allow-same-origin", "allow-scripts"],
        style_src: [:self, {:sha384, "YWJj"}, :unsafe_hashes],
        upgrade_insecure_requests: true
      )

      assert validate_config!() == :ok
    end

    test "passes for a config removing every directive" do
      put_config(
        base_uri: false,
        form_action: false,
        frame_ancestors: false,
        object_src: false,
        script_src: false
      )

      assert validate_config!() == :ok
    end

    test "passes for Trusted Types enforced with the app's own policies" do
      put_config(
        require_trusted_types_for: [:script],
        trusted_types: ["default", :allow_duplicates]
      )

      assert validate_config!() == :ok
    end

    # 'none' beside policy names is ignored by the browser.
    test "passes for a trusted_types directive naming :none beside a policy" do
      put_config(trusted_types: [:none, "default"])

      assert validate_config!() == :ok
    end

    test "passes for a policy without a nonce that lets the runtime load from its own origin" do
      put_config(script_src: [:self, :unsafe_inline])

      assert validate_config!() == :ok
    end

    test "raises for a value that is not a keyword list" do
      put_config(%{img_src: [:self]})

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy must be a keyword list of directives or false, but received %{img_src: [:self]}",
                   fn -> validate_config!() end
    end

    test "raises for an unknown directive" do
      put_config(img_srcc: [:self])

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy names an unknown directive: :img_srcc",
                   fn -> validate_config!() end
    end

    test "raises for a directive given more than once" do
      put_config(img_src: [:self], img_src: ["data:"])

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy gives the :img_src directive more than once",
                   fn -> validate_config!() end
    end

    test "raises for a directive value that is not a list" do
      put_config(img_src: :self)

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy gives the :img_src directive :self, but it takes a list of sources or false",
                   fn -> validate_config!() end
    end

    test "raises for true given to a directive that takes sources" do
      put_config(img_src: true)

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy gives the :img_src directive true, but it takes a list of sources or false",
                   fn -> validate_config!() end
    end

    test "passes for a switch directive set to false" do
      put_config(upgrade_insecure_requests: false)

      assert validate_config!() == :ok
    end

    test "raises for a list given to a switch directive" do
      put_config(upgrade_insecure_requests: ["https:"])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy gives the :upgrade_insecure_requests directive ["https:"], but it takes true or false),
                   fn -> validate_config!() end
    end

    test "raises for an empty list given to a switch directive" do
      put_config(upgrade_insecure_requests: [])

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy gives the :upgrade_insecure_requests directive [], but it takes true or false",
                   fn -> validate_config!() end
    end

    test "raises for an unknown keyword" do
      put_config(img_src: [:selff])

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy gives the :img_src directive an unknown keyword: :selff",
                   fn -> validate_config!() end
    end

    test "raises for a keyword the directive doesn't take" do
      put_config(script_src: [:nonce, :script])

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy gives the :script_src directive the keyword :script, which it doesn't take",
                   fn -> validate_config!() end
    end

    test "raises for a source keyword in a directive with keywords of its own" do
      put_config(require_trusted_types_for: [:self])

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy gives the :require_trusted_types_for directive the keyword :self, which it doesn't take",
                   fn -> validate_config!() end
    end

    # A browser drops require-trusted-types-for without 'script', leaving Trusted Types unenforced.
    test "raises for require_trusted_types_for without :script" do
      put_config(require_trusted_types_for: [])

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy gives the :require_trusted_types_for directive [], but it takes [:script]",
                   fn -> validate_config!() end
    end

    test "raises for a Trusted Types policy name outside the grammar's alphabet" do
      put_config(trusted_types: ["https:"])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy gives the :trusted_types directive the policy name "https:", but a policy name holds only letters, digits and - # = _ / @ . %, or is *),
                   fn -> validate_config!() end
    end

    test "raises for a source that is neither a keyword, a string nor a hash" do
      put_config(img_src: [123])

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy gives the :img_src directive the source 123, but a source is a keyword atom, a string, or a {:sha256 | :sha384 | :sha512, base64} tuple",
                   fn -> validate_config!() end
    end

    test "raises for a hash of an unknown algorithm" do
      put_config(style_src: [{:md5, "YWJj"}])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy gives the :style_src directive the source {:md5, "YWJj"}, but a source is a keyword atom, a string, or a {:sha256 | :sha384 | :sha512, base64} tuple),
                   fn -> validate_config!() end
    end

    test "raises for a hash whose digest is not base64" do
      put_config(style_src: [{:sha256, "not base64!"}])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy gives the :style_src directive a :sha256 hash whose digest "not base64!" is not base64),
                   fn -> validate_config!() end
    end

    test "raises for a hash whose digest ends in a newline" do
      put_config(style_src: [{:sha256, "YWJj\n"}])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy gives the :style_src directive a :sha256 hash whose digest "YWJj\\n" is not base64),
                   fn -> validate_config!() end
    end

    test "raises for a hash whose digest has more padding than base64 takes" do
      put_config(style_src: [{:sha256, "YWJj==="}])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy gives the :style_src directive a :sha256 hash whose digest "YWJj===" is not base64),
                   fn -> validate_config!() end
    end

    # A source is written into the header as it is, so these would end it early and start another
    # source or directive.
    test "raises for a source holding a semicolon" do
      put_config(img_src: ["https://a.com; script-src *"])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy gives the :img_src directive the source "https://a.com; script-src *", but a source is visible ASCII without a semicolon or a comma, and not empty),
                   fn -> validate_config!() end
    end

    test "raises for a source holding a comma" do
      put_config(img_src: ["https://a.com,https://b.com"])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy gives the :img_src directive the source "https://a.com,https://b.com", #{@source_message}),
                   fn -> validate_config!() end
    end

    test "raises for a source holding whitespace" do
      put_config(img_src: ["https://a.com https://b.com"])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy gives the :img_src directive the source "https://a.com https://b.com", #{@source_message}),
                   fn -> validate_config!() end
    end

    test "raises for a source holding a control character" do
      source = "https://a.com\0"
      put_config(img_src: [source])

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy gives the :img_src directive the source #{inspect(source)}, #{@source_message}",
                   fn -> validate_config!() end
    end

    test "raises for a source holding a character beyond ASCII" do
      put_config(img_src: ["https://ä.com"])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy gives the :img_src directive the source "https://ä.com", #{@source_message}),
                   fn -> validate_config!() end
    end

    test "raises for an empty source" do
      put_config(img_src: [""])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy gives the :img_src directive the source "", but a source is visible ASCII without a semicolon or a comma, and not empty),
                   fn -> validate_config!() end
    end

    test "passes for a policy naming the nonce through default_src alone" do
      put_config(default_src: [:self, :nonce], script_src: false)

      assert validate_config!() == :ok
    end

    test "raises for a script policy without a nonce and with 'unsafe-inline' alone" do
      put_config(script_src: [:unsafe_inline])

      assert_error ArgumentError, unbootable_scripts_message(:script_src), fn ->
        validate_config!()
      end
    end

    test "raises for a script element policy that overrides a bootable script policy" do
      put_config(script_src_elem: [:self])

      assert_error ArgumentError, unbootable_scripts_message(:script_src_elem), fn ->
        validate_config!()
      end
    end

    # A browser ignores 'unsafe-inline' and 'self' beside 'strict-dynamic'.
    test "raises for a script policy without a nonce whose 'unsafe-inline' 'strict-dynamic' voids" do
      put_config(script_src: [:self, :strict_dynamic, :unsafe_inline])

      assert_error ArgumentError, unbootable_scripts_message(:script_src), fn ->
        validate_config!()
      end
    end

    # A browser ignores 'unsafe-inline' beside a hash, and no hash can allow the shell, which holds
    # the per-page nonce.
    test "raises for a script policy without a nonce whose 'unsafe-inline' a hash voids" do
      put_config(script_src: [:self, :unsafe_inline, {:sha256, "YWJj"}])

      assert_error ArgumentError, unbootable_scripts_message(:script_src), fn ->
        validate_config!()
      end
    end

    test "raises for a connection policy that doesn't allow the app's own server" do
      put_config(default_src: [:none])

      assert_error ArgumentError,
                   "config :hologram, :content_security_policy describes a policy no Hologram page could work under: :default_src, the directive governing the connections the runtime makes to its server, allows neither :self nor a source naming the server",
                   fn -> validate_config!() end
    end

    test "passes for a connection policy that allows the app's own server" do
      put_config(default_src: [:none], connect_src: [:self])

      assert validate_config!() == :ok
    end

    test "raises for a sandbox without allow-scripts and allow-same-origin" do
      put_config(sandbox: [])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy describes a policy no Hologram page could work under: :sandbox lacks "allow-same-origin" and "allow-scripts", which the runtime needs to run and to reach its server),
                   fn -> validate_config!() end
    end

    test "raises for a trusted_types directive allowing no policy" do
      put_config(require_trusted_types_for: [:script], trusted_types: [])

      assert_error ArgumentError, @no_trusted_types_policy_message, fn ->
        validate_config!()
      end
    end

    test "raises for a trusted_types directive naming :none alone" do
      put_config(trusted_types: [:none, :allow_duplicates])

      assert_error ArgumentError, @no_trusted_types_policy_message, fn ->
        validate_config!()
      end
    end

    test "raises for a sandbox without allow-same-origin" do
      put_config(sandbox: ["allow-scripts"])

      assert_error ArgumentError,
                   ~s(config :hologram, :content_security_policy describes a policy no Hologram page could work under: :sandbox lacks "allow-same-origin", which the runtime needs to run and to reach its server),
                   fn -> validate_config!() end
    end
  end
end
