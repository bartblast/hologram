defmodule Hologram do
  alias Hologram.Reflection

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
  """
  @spec env() :: atom
  def env do
    env_str = System.get_env("HOLOGRAM_ENV") || System.get_env("MIX_ENV")

    if env_str do
      String.to_existing_atom(env_str)
    else
      detect_env()
    end
  end

  @doc """
  Returns the secret key base.

  Uses the `SECRET_KEY_BASE` env var when set. In :dev/:test, falls back to the
  Phoenix endpoint's configured `:secret_key_base`. In all other environments the
  env var is required.
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
