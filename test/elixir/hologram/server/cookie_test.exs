defmodule Hologram.Server.CookieTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Server.Cookie

  describe "encode/1" do
    test "encodes a string" do
      result = Cookie.encode("hello world")

      assert result == "%Hg20AAAALaGVsbG8gd29ybGQ"
    end

    test "encodes a non-string" do
      result = Cookie.encode([1, 2, 3])

      assert result == "%Hg2sAAwECAw"
    end

    test "encoding is deterministic" do
      term = %{user_id: 123, role: :admin}

      assert Cookie.encode(term) == Cookie.encode(term)
    end

    test "encoded value contains no padding characters" do
      # If padding was applied the result would have a "=" character
      result = Cookie.encode("Hologram")

      refute String.contains?(result, "=")
    end
  end
end
