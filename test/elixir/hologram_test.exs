defmodule HologramTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram

  alias Hologram.Test.Fixtures.PhoenixEndpoint

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

  test "env/0" do
    assert env() == :test
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
