defmodule Hologram do
  alias Hologram.Reflection

  @doc """
  Returns `true` when the client-side runtime error overlay is enabled, `false`
  otherwise.

  Controlled by the `:client_error_overlay` application environment key, which
  defaults to whatever `client_stacktraces?/0` returns, so turning client
  diagnostics on turns both on:

      config :hologram, client_error_overlay: false

  When enabled, an uncaught client error renders in the page as well as in the
  browser console. Uncaught errors reach the console in every environment - this
  setting only decides whether they are also shown in the page.

  Setting it to `false` alongside enabled stacktraces leaves the report in the
  console without putting an error screen in front of the app's users. The two
  reach different people: console output is read by whoever opens the devtools,
  whereas the overlay is shown to everyone who hits the error.

  The value is read at compile time, so changing it requires recompiling the
  bundles.
  """
  @spec client_error_overlay?() :: boolean
  def client_error_overlay? do
    Application.get_env(:hologram, :client_error_overlay, client_stacktraces?())
  end

  @doc """
  Returns `true` when client-side stacktraces are enabled, `false` otherwise.

  Controlled by the `:client_stacktraces` application environment key, which
  defaults to `true` in the `:dev` and `:test` environments and `false`
  elsewhere:

      config :hologram, client_stacktraces: true

  When enabled, the compiler emits source metadata into the client bundle and
  the interpreter tracks a call stack, so errors raised on the client carry the
  same stacktraces as errors raised on the server. Error messages and rescue
  semantics are unaffected by this setting - they are identical in every
  environment.

  Enabling it outside of `:dev`/`:test` has trade-offs: argument values appear
  in stacktrace frames and can leave the device via screenshots, support tickets
  or pasted console output, source paths reveal the project's file layout, and
  the compiled Elixir in a bundle is roughly a third larger over the wire.

  The value is read at compile time, so changing it requires recompiling the
  bundles.
  """
  @spec client_stacktraces?() :: boolean
  def client_stacktraces? do
    Application.get_env(:hologram, :client_stacktraces, env() in [:dev, :test])
  end

  @doc """
  Returns `true` when Hologram's runtime is enabled, `false` otherwise.

  Hologram is always enabled outside of the `:dev` and `:test` environments. In
  `:dev` and `:test` it is disabled unless the `HOLOGRAM_START` environment
  variable is set to `"1"` (as `mix holo` does). When disabled, Hologram's
  supervision children are not started and `Hologram.Router` passes requests
  straight through to the next plug instead of trying to serve them.
  """
  @spec enabled?() :: boolean
  def enabled? do
    env() not in [:dev, :test] or System.get_env("HOLOGRAM_START") == "1"
  end

  @doc """
  Returns the current environment.

  Named by `HOLOGRAM_ENV`, or `MIX_ENV` when it is unset - any name the deployment
  uses, not only `:dev`, `:test` and `:prod`. With neither var set, the environment
  is detected.
  """
  @spec env() :: atom
  # The name comes from the deployment's own configuration - an env var whoever runs the
  # release sets - so the atoms this can create are bounded by the environments they run,
  # never by anything a request carries. Requiring an existing atom instead would tie the
  # framework to Mix: a release carries no Mix, so an environment name that no loaded
  # module happens to mention has no atom yet, and the boot dies on it (found 2026-08-13
  # booting a bare node as "prod").
  # sobelow_skip ["DOS.StringToAtom"]
  def env do
    env_str = System.get_env("HOLOGRAM_ENV") || System.get_env("MIX_ENV")

    if env_str do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      String.to_atom(env_str)
    else
      detect_env()
    end
  end

  @doc """
  Returns the secret key base.

  Uses the `SECRET_KEY_BASE` env var when set. In embedded mode, `:dev` and
  `:test` fall back to the Phoenix endpoint's configured `:secret_key_base` -
  standalone mode has no endpoint to read it from. Everywhere else the env var
  is required.
  """
  @spec secret_key_base() :: String.t()
  def secret_key_base do
    System.get_env("SECRET_KEY_BASE") || dev_test_secret_key_base()
  end

  defp detect_env do
    if Process.whereis(ExUnit.Server) do
      :test
    else
      :dev
    end
  end

  defp dev_test_secret_key_base do
    # NOTE: Hologram.env/0 defaults to :dev when neither HOLOGRAM_ENV nor MIX_ENV
    # is set (possible in a release). Harmless here: a real prod release either has
    # SECRET_KEY_BASE set (handled above) or Phoenix's runtime.exs already raised.
    if env() in [:dev, :test] do
      endpoint = Reflection.phoenix_endpoint()
      otp_app = Reflection.otp_app()

      (endpoint && Application.get_env(otp_app, endpoint)[:secret_key_base]) ||
        raise """
        Hologram could not resolve a secret key base. Set the SECRET_KEY_BASE \
        environment variable, or configure :secret_key_base on your Phoenix \
        endpoint (config :my_app, MyAppWeb.Endpoint, secret_key_base: ...).
        """
    else
      raise "Hologram requires the SECRET_KEY_BASE environment variable to be set in this environment."
    end
  end
end
