defmodule Hologram.Runtime.ContentSecurityPolicy do
  @moduledoc false

  @config_error_prefix "config :hologram, :content_security_policy"

  # Strict CSP as Google and OWASP publish it: scripts run by nonce, and those may load more
  # ('strict-dynamic'), which is what stops injected scripts, and object-src and base-uri close the
  # two classic ways around that. 'unsafe-inline' is the fallback for browsers without nonces,
  # which ignore it once they have them, and https: the one for browsers without 'strict-dynamic',
  # which ignore it once they have that. Beside them the two hardening directives OWASP lists:
  # form-action against an injected form collecting what users type, and frame-ancestors against
  # clickjacking, letting the app's own pages frame each other. Nothing restricts images, fonts,
  # styles, frames or connections, which carry no code.
  @default_directives [
    base_uri: [:none],
    form_action: [:self],
    frame_ancestors: [:self],
    object_src: [:none],
    script_src: [:nonce, :strict_dynamic, :unsafe_inline, "https:"]
  ]

  # CSP Level 3 (https://www.w3.org/TR/CSP3/#csp-directives), with the directives other
  # specifications add to it: fenced-frame-src (Fenced Frame), require-trusted-types-for and
  # trusted-types (Trusted Types), upgrade-insecure-requests (Upgrade Insecure Requests).
  @directive_names [
    :base_uri,
    :child_src,
    :connect_src,
    :default_src,
    :fenced_frame_src,
    :font_src,
    :form_action,
    :frame_ancestors,
    :frame_src,
    :img_src,
    :manifest_src,
    :media_src,
    :object_src,
    :report_to,
    :report_uri,
    :require_trusted_types_for,
    :sandbox,
    :script_src,
    :script_src_attr,
    :script_src_elem,
    :style_src,
    :style_src_attr,
    :style_src_elem,
    :trusted_types,
    :upgrade_insecure_requests,
    :webrtc,
    :worker_src
  ]

  @hash_algorithms [:sha256, :sha384, :sha512]

  # The keywords three directives take instead of the source keywords, each only where it belongs.
  @directive_keywords %{
    require_trusted_types_for: [:script],
    trusted_types: [:allow_duplicates, :none],
    webrtc: [:allow, :block]
  }

  # The keywords, written quoted: :self is 'self', :unsafe_inline is 'unsafe-inline'.
  @keywords [
    :allow,
    :allow_duplicates,
    :block,
    :inline_speculation_rules,
    :none,
    :nonce,
    :report_sample,
    :report_sha256,
    :report_sha384,
    :report_sha512,
    :script,
    :self,
    :strict_dynamic,
    :trusted_types_eval,
    :unsafe_eval,
    :unsafe_hashes,
    :unsafe_inline,
    :unsafe_webtransport_hashes,
    :wasm_unsafe_eval
  ]

  # The directives that govern a kind of request, the one the browser reads first coming first: an
  # element directive when present, else the directive for its kind, else default-src.
  @connect_directives [:connect_src, :default_src]
  @script_element_directives [:script_src_elem, :script_src, :default_src]
  @style_element_directives [:style_src_elem, :style_src, :default_src]

  # The keywords a source list takes, which every directive but those three does: the fetch
  # directives, base-uri, form-action and frame-ancestors among them. 'none' is in both kinds.
  @source_keywords @keywords -- [:allow, :allow_duplicates, :block, :script]

  # The directives that take no sources, each a switch: true writes its bare name, false removes it.
  @switch_directives [:upgrade_insecure_requests]

  @doc """
  Returns the policy the rendered pages are sent with: Hologram's default directives with the
  app's `config :hologram, :content_security_policy` merged over them, sorted by directive name,
  or `nil` when the app turned the policy off with `false`.

  A directive the config gives replaces the default for that directive, and one set to `false` is
  removed. A switch directive, which takes no sources, is set to `true` to turn it on. A config
  removing every directive is no policy either. Read at call time, so the key
  works from `config/runtime.exs`.

  A `trusted_types` directive the config gives has Hologram's own Trusted Types policy,
  `"hologram"`, added to the names it allows, since the runtime creates it to run its scripts.

  ## Examples

      iex> directives()
      [
        base_uri: [:none],
        form_action: [:self],
        frame_ancestors: [:self],
        object_src: [:none],
        script_src: [:nonce, :strict_dynamic, :unsafe_inline, "https:"]
      ]
  """
  @spec directives() :: keyword([atom | String.t() | {atom, String.t()}] | true) | nil
  def directives do
    case Application.get_env(:hologram, :content_security_policy, []) do
      false ->
        nil

      config ->
        directives =
          @default_directives
          |> Keyword.merge(config)
          |> Enum.reject(fn {_name, sources} -> sources == false end)
          |> maybe_allow_hologram_trusted_types_policy()
          |> Enum.sort_by(fn {name, _sources} -> name end)

        if directives != [], do: directives
    end
  end

  @doc """
  Generates a nonce for one rendered page: 128 bits of randomness in the base64 alphabet a
  Content Security Policy nonce source is written in.

  ## Examples

      iex> generate_nonce()
      "f2KQWpHYuoeTQ1ZlbtX4pA=="
  """
  @spec generate_nonce() :: String.t()
  def generate_nonce do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
  end

  @doc """
  Renders the given directives as the value of a `content-security-policy` header, with the given
  nonce where a directive names `:nonce`.

  A directive name is written with hyphens. A keyword atom is written quoted with hyphens, `:nonce`
  as the nonce source, a string as it is, and a hash tuple as a hash source. A switch directive set
  to `true` is written as its bare name, and so is a directive given an empty list.

  ## Examples

      iex> header_value([img_src: [:self, "data:"], script_src: [:nonce]], "abc")
      "img-src 'self' data:; script-src 'nonce-abc'"

      iex> header_value([upgrade_insecure_requests: true], "abc")
      "upgrade-insecure-requests"
  """
  @spec header_value(keyword([atom | String.t() | {atom, String.t()}] | true), String.t()) ::
          String.t()
  def header_value(directives, nonce) do
    Enum.map_join(directives, "; ", &render_directive(&1, nonce))
  end

  @doc """
  The elements a page sent with the given directives stamps with its nonce: the ones a directive
  names the nonce for. `"script"` when the directive governing script elements names `:nonce`,
  `"link"` and `"style"` when the one governing style elements does, none for no policy (`nil`).

  The governing directive is the one the browser reads: `script_src_elem` when present, else
  `script_src`, else `default_src`, and likewise for styles.

  ## Examples

      iex> nonced_elements(directives())
      ["script"]
  """
  @spec nonced_elements(keyword | nil) :: [String.t()]
  def nonced_elements(directives) do
    case directives do
      nil ->
        []

      directives ->
        script_elements =
          if :nonce in governing_sources(directives, @script_element_directives),
            do: ["script"],
            else: []

        style_elements =
          if :nonce in governing_sources(directives, @style_element_directives),
            do: ["link", "style"],
            else: []

        Enum.sort(script_elements ++ style_elements)
    end
  end

  @doc """
  Checks `config :hologram, :content_security_policy`, raising `ArgumentError` with a message naming
  the offending entry when the config is malformed, or when no Hologram page could boot under the
  policy it describes. Run when the app starts, so a bad config fails the boot rather than the
  first request.
  """
  @spec validate_config!() :: :ok
  def validate_config! do
    case Application.get_env(:hologram, :content_security_policy, []) do
      false ->
        :ok

      config ->
        validate_keyword_list!(config)
        Enum.each(config, &validate_directive!/1)
        validate_unique_names!(config)

        validate_trusted_types!(config)

        case directives() do
          nil ->
            :ok

          directives ->
            validate_scripts_bootable!(directives)
            validate_connections_bootable!(directives)
            validate_sandbox_bootable!(directives)

            :ok
        end
    end
  end

  defp governing_directive(directives, directive_names) do
    Enum.find_value(directive_names, fn name ->
      if Keyword.has_key?(directives, name), do: {name, Keyword.fetch!(directives, name)}
    end)
  end

  defp governing_sources(directives, directive_names) do
    case governing_directive(directives, directive_names) do
      {_name, sources} -> sources
      nil -> []
    end
  end

  # A trusted-types directive allows only the policy names it lists, and the runtime creates its own.
  # Without the directive any name is allowed, so none is added, which would forbid the app's own.
  defp maybe_allow_hologram_trusted_types_policy(directives) do
    case Keyword.fetch(directives, :trusted_types) do
      {:ok, names} ->
        if "hologram" in names,
          do: directives,
          else: Keyword.put(directives, :trusted_types, ["hologram" | names])

      :error ->
        directives
    end
  end

  # Each raises itself rather than through the other, since a function that only calls one which
  # never returns is one Dialyzer reports as having no local return.
  defp raise_config_error(message) do
    raise ArgumentError, "#{@config_error_prefix} #{message}"
  end

  defp raise_unbootable_error(reason) do
    raise ArgumentError,
          "#{@config_error_prefix} describes a policy no Hologram page could work under: #{reason}"
  end

  defp render_directive({name, true}, _nonce), do: render_name(name)

  defp render_directive({name, sources}, nonce) do
    rendered_sources = Enum.map(sources, &render_source(&1, nonce))
    Enum.join([render_name(name) | rendered_sources], " ")
  end

  defp render_name(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp render_source(:nonce, nonce), do: "'nonce-#{nonce}'"

  defp render_source(keyword, _nonce) when is_atom(keyword) do
    "'#{render_name(keyword)}'"
  end

  defp render_source({algorithm, digest}, _nonce), do: "'#{algorithm}-#{digest}'"

  defp render_source(source, _nonce) when is_binary(source), do: source

  # The runtime talks to its own server: actions' commands, navigations and the realtime stream.
  defp validate_connections_bootable!(directives) do
    case governing_directive(directives, @connect_directives) do
      nil ->
        :ok

      {name, sources} ->
        if not (:self in sources or Enum.any?(sources, &is_binary/1)) do
          raise_unbootable_error(
            "#{inspect(name)}, the directive governing the connections the runtime makes to its " <>
              "server, allows neither :self nor a source naming the server"
          )
        end
    end
  end

  defp validate_directive!({name, sources}) do
    if name not in @directive_names do
      raise_config_error("names an unknown directive: #{inspect(name)}")
    end

    cond do
      sources == false ->
        :ok

      name in @switch_directives ->
        if sources != true do
          raise_config_error(
            "gives the #{inspect(name)} directive #{inspect(sources)}, but it takes true or false"
          )
        end

      is_list(sources) ->
        Enum.each(sources, &validate_source!(name, &1))

      true ->
        raise_config_error(
          "gives the #{inspect(name)} directive #{inspect(sources)}, " <>
            "but it takes a list of sources or false"
        )
    end
  end

  defp validate_keyword_list!(config) do
    if not Keyword.keyword?(config) do
      raise_config_error(
        "must be a keyword list of directives or false, but received #{inspect(config)}"
      )
    end
  end

  # A sandboxed document runs no script without allow-scripts, and without allow-same-origin it has
  # an opaque origin, from which the runtime's requests to its own server are cross-origin ones.
  defp validate_sandbox_bootable!(directives) do
    case Keyword.fetch(directives, :sandbox) do
      {:ok, flags} ->
        missing_flags = ["allow-same-origin", "allow-scripts"] -- flags

        if missing_flags != [] do
          raise_unbootable_error(
            ":sandbox lacks #{Enum.map_join(missing_flags, " and ", &inspect/1)}, " <>
              "which the runtime needs to run and to reach its server"
          )
        end

      :error ->
        :ok
    end
  end

  # The shell is an inline script and the runtime an external one. A nonce allows both. Without one,
  # 'unsafe-inline' allows the shell, and 'self' or a source naming where the runtime is served from
  # allows the runtime, but a browser ignores 'unsafe-inline' beside a hash, and both beside
  # 'strict-dynamic'. No hash can allow the shell, since it holds the per-page nonce.
  defp validate_scripts_bootable!(directives) do
    case governing_directive(directives, @script_element_directives) do
      nil ->
        :ok

      {name, sources} ->
        inline_allowed? =
          :unsafe_inline in sources and :strict_dynamic not in sources and
            not Enum.any?(sources, &is_tuple/1)

        external_allowed? = :self in sources or Enum.any?(sources, &is_binary/1)

        if not (:nonce in sources or (inline_allowed? and external_allowed?)) do
          raise_unbootable_error(
            "#{inspect(name)}, the directive governing script elements, names no :nonce, " <>
              "and allows the inline shell script through :unsafe_inline together with :self " <>
              "or a source the runtime is served from only without :strict_dynamic and without " <>
              "a hash, which make browsers ignore :unsafe_inline"
          )
        end
    end
  end

  defp validate_source!(name, keyword) when is_atom(keyword) do
    cond do
      keyword not in @keywords ->
        raise_config_error(
          "gives the #{inspect(name)} directive an unknown keyword: #{inspect(keyword)}"
        )

      keyword not in Map.get(@directive_keywords, name, @source_keywords) ->
        raise_config_error(
          "gives the #{inspect(name)} directive the keyword #{inspect(keyword)}, " <>
            "which it doesn't take"
        )

      true ->
        :ok
    end
  end

  # A source is written into the header as it is. The grammar takes visible ASCII without a
  # semicolon or a comma, which would end it early and start another directive or policy, and a
  # header can't carry a control character at all.
  defp validate_source!(name, source) when is_binary(source) do
    if not String.match?(source, ~r/\A[\x21-\x2B\x2D-\x3A\x3C-\x7E]+\z/) do
      raise_config_error(
        "gives the #{inspect(name)} directive the source #{inspect(source)}, but a source is " <>
          "visible ASCII without a semicolon or a comma, and not empty"
      )
    end
  end

  defp validate_source!(name, {algorithm, digest})
       when algorithm in @hash_algorithms and is_binary(digest) do
    if not String.match?(digest, ~r'\A[A-Za-z0-9+/_-]+={0,2}\z') do
      raise_config_error(
        "gives the #{inspect(name)} directive a #{inspect(algorithm)} hash whose digest " <>
          "#{inspect(digest)} is not base64"
      )
    end
  end

  defp validate_source!(name, source) do
    raise_config_error(
      "gives the #{inspect(name)} directive the source #{inspect(source)}, but a source is " <>
        "a keyword atom, a string, or a {:sha256 | :sha384 | :sha512, base64} tuple"
    )
  end

  # require-trusted-types-for takes 'script' alone, and a browser drops it with any other value,
  # leaving Trusted Types unenforced. trusted-types allows the policy names it lists, so one listing
  # none - empty, or 'none' alone - forbids Hologram's own, while 'none' beside names is ignored.
  # A name is in the grammar's alphabet, or the * that allows every one.
  defp validate_trusted_types!(config) do
    case Keyword.get(config, :require_trusted_types_for) do
      sources when is_list(sources) and sources != [:script] ->
        raise_config_error(
          "gives the :require_trusted_types_for directive #{inspect(sources)}, " <>
            "but it takes [:script]"
        )

      _sources ->
        :ok
    end

    case Keyword.get(config, :trusted_types) do
      sources when is_list(sources) ->
        names = Enum.filter(sources, &is_binary/1)

        if names == [] do
          raise_unbootable_error(
            ":trusted_types allows no Trusted Types policy, Hologram's own among them, " <>
              "so list the policies the app creates, or \"*\" for every one"
          )
        end

        Enum.each(names, &validate_trusted_types_policy_name!/1)

      _sources ->
        :ok
    end
  end

  defp validate_trusted_types_policy_name!(name) do
    if name != "*" and not String.match?(name, ~r'\A[A-Za-z0-9\-#=_/@.%]+\z') do
      raise_config_error(
        "gives the :trusted_types directive the policy name #{inspect(name)}, but a policy name " <>
          "holds only letters, digits and - # = _ / @ . %, or is *"
      )
    end
  end

  defp validate_unique_names!(config) do
    duplicate_name =
      config
      |> Keyword.keys()
      |> Enum.frequencies()
      |> Enum.find_value(fn {name, count} -> if count > 1, do: name end)

    if duplicate_name do
      raise_config_error("gives the #{inspect(duplicate_name)} directive more than once")
    end
  end
end
