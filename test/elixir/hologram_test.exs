defmodule HologramTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram

  alias Hologram.Test.Fixtures.PhoenixEndpoint

  describe "client_error_overlay?/0" do
    setup do
      on_exit(fn ->
        Application.delete_env(:hologram, :client_error_overlay)
        Application.delete_env(:hologram, :client_stacktraces)
      end)

      :ok
    end

    test "follows enabled stacktraces when the config key is not set" do
      Application.delete_env(:hologram, :client_error_overlay)
      Application.put_env(:hologram, :client_stacktraces, true)

      assert client_error_overlay?()
    end

    test "follows disabled stacktraces when the config key is not set" do
      Application.delete_env(:hologram, :client_error_overlay)
      Application.put_env(:hologram, :client_stacktraces, false)

      refute client_error_overlay?()
    end

    test "is true when the config key is set to true" do
      Application.put_env(:hologram, :client_error_overlay, true)

      assert client_error_overlay?()
    end

    test "is false when the config key is set to false" do
      Application.put_env(:hologram, :client_error_overlay, false)

      refute client_error_overlay?()
    end

    test "is false with stacktraces enabled when the config key is set to false" do
      Application.put_env(:hologram, :client_error_overlay, false)
      Application.put_env(:hologram, :client_stacktraces, true)

      refute client_error_overlay?()
    end
  end

  describe "client_stacktraces?/0" do
    setup do
      on_exit(fn -> Application.delete_env(:hologram, :client_stacktraces) end)

      :ok
    end

    test "defaults to true in dev/test when the config key is not set" do
      Application.delete_env(:hologram, :client_stacktraces)

      assert client_stacktraces?()
    end

    test "is true when the config key is set to true" do
      Application.put_env(:hologram, :client_stacktraces, true)

      assert client_stacktraces?()
    end

    test "is false when the config key is set to false" do
      Application.put_env(:hologram, :client_stacktraces, false)

      refute client_stacktraces?()
    end
  end

  describe "enabled?/0" do
    setup do
      original = System.get_env("HOLOGRAM_START")

      on_exit(fn ->
        if original do
          System.put_env("HOLOGRAM_START", original)
        else
          System.delete_env("HOLOGRAM_START")
        end
      end)

      :ok
    end

    test "is false in dev/test when HOLOGRAM_START is not set" do
      System.delete_env("HOLOGRAM_START")

      refute enabled?()
    end

    test "is true in dev/test when HOLOGRAM_START is set to \"1\"" do
      System.put_env("HOLOGRAM_START", "1")

      assert enabled?()
    end
  end

  describe "env/0" do
    setup do
      original = System.get_env("HOLOGRAM_ENV")

      on_exit(fn ->
        if original do
          System.put_env("HOLOGRAM_ENV", original)
        else
          System.delete_env("HOLOGRAM_ENV")
        end
      end)

      :ok
    end

    test "returns the current environment" do
      assert env() == :test
    end

    test "returns an environment whose atom does not exist yet" do
      System.put_env("HOLOGRAM_ENV", "staging")

      assert env() == :staging
    end
  end

  describe "secret_key_base/0" do
    setup do
      original = System.get_env("SECRET_KEY_BASE")

      on_exit(fn ->
        if original do
          System.put_env("SECRET_KEY_BASE", original)
        else
          System.delete_env("SECRET_KEY_BASE")
        end

        Application.delete_env(:hologram, PhoenixEndpoint)
      end)

      :ok
    end

    test "uses the SECRET_KEY_BASE env var when set" do
      System.put_env("SECRET_KEY_BASE", "env-var-secret")

      assert secret_key_base() == "env-var-secret"
    end

    test "falls back to the endpoint's secret_key_base in dev/test when the env var is absent" do
      System.delete_env("SECRET_KEY_BASE")
      Application.put_env(:hologram, PhoenixEndpoint, secret_key_base: "endpoint-secret")

      assert secret_key_base() == "endpoint-secret"
    end

    test "raises in dev/test when neither the env var nor an endpoint secret is configured" do
      System.delete_env("SECRET_KEY_BASE")

      assert_raise RuntimeError, ~r/could not resolve a secret key base/, fn ->
        secret_key_base()
      end
    end
  end
end
