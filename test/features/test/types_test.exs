defmodule HologramFeatureTests.TypesTest do
  use HologramFeatureTests.TestCase, async: true

  alias Hologram.Commons.SystemUtils
  alias HologramFeatureTests.TypesPage

  feature "atom", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='atom']"))
    |> assert_text(css("#result"), inspect(:abc))
  end

  describe "bitstring" do
    feature "binary", %{session: session} do
      session
      |> visit(TypesPage)
      |> click(css("button[id='bitstring (binary)']"))
      |> assert_text(css("#result"), inspect("abc"))
    end

    feature "non-binary", %{session: session} do
      session
      |> visit(TypesPage)
      |> click(css("button[id='bitstring (non-binary)']"))
      |> assert_text(css("#result"), inspect(<<1::1, 0::1, 1::1, 0::1>>))
    end
  end

  feature "float", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='float']"))
    |> assert_text(css("#result"), inspect(1.23))
  end

  describe "function" do
    feature "anonymous (client origin, non-capture)", %{session: session} do
      assert_js_error session,
                      "can't encode client terms that are anonymous functions that are not named function captures",
                      fn ->
                        session
                        |> visit(TypesPage)
                        |> click(
                          css("button[id='anonymous function (client origin, non-capture)']")
                        )
                      end

      assert_text(session, css("#result"), inspect(8))
    end

    feature "anonymous (server origin, non-capture)", %{session: session} do
      expected_msg =
        if SystemUtils.otp_version() >= 23 do
          "command failed: term contains an anonymous function that is not a named function capture"
        else
          "command failed: term contains an anonymous function that is not a remote function capture"
        end

      assert_js_error session, expected_msg, fn ->
        session
        |> visit(TypesPage)
        |> click(css("button[id='anonymous function (server origin, non-capture)']"))
      end
    end

    feature "anonymous (server origin, capture)", %{session: session} do
      expected_msg =
        if SystemUtils.otp_version() >= 23 do
          "command failed: term contains an anonymous function that is not a named function capture"
        else
          "command failed: term contains an anonymous function that is not a remote function capture"
        end

      assert_js_error session, expected_msg, fn ->
        session
        |> visit(TypesPage)
        |> click(css("button[id='anonymous function (server origin, capture)']"))
      end
    end

    feature "anonymous (client origin, capture)", %{session: session} do
      assert_js_error session,
                      "can't encode client terms that are anonymous functions that are not named function captures",
                      fn ->
                        session
                        |> visit(TypesPage)
                        |> click(css("button[id='anonymous function (client origin, capture)']"))
                      end

      assert_text(session, css("#result"), inspect(8))
    end

    feature "local capture (client origin)", %{session: session} do
      session
      |> visit(TypesPage)
      |> click(css("button[id='local function capture (client origin)']"))
      |> assert_text(css("#result"), "client = 8, server = 8")
    end

    feature "local capture (server origin)", %{session: session} do
      if SystemUtils.otp_version() >= 23 do
        session
        |> visit(TypesPage)
        |> click(css("button[id='local function capture (server origin)']"))
        |> assert_text(css("#result"), inspect(8))
      else
        assert_js_error session,
                        "command failed: term contains an anonymous function that is not a remote function capture",
                        fn ->
                          session
                          |> visit(TypesPage)
                          |> click(css("button[id='local function capture (server origin)']"))
                        end
      end
    end

    feature "remote capture (client origin)", %{session: session} do
      session
      |> visit(TypesPage)
      |> click(css("button[id='remote function capture (client origin)']"))
      |> assert_text(css("#result"), "client = 8, server = 8")
    end

    feature "remote capture (server origin)", %{session: session} do
      session
      |> visit(TypesPage)
      |> click(css("button[id='remote function capture (server origin)']"))
      |> assert_text(css("#result"), inspect(8))
    end
  end

  feature "integer", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='integer']"))
    |> assert_text(css("#result"), inspect(123))
  end

  feature "list", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='list']"))
    |> assert_text(css("#result"), inspect([123, :abc]))
  end

  feature "map", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='map']"))
    |> assert_text(css("#result"), inspect(%{a: 123, b: "abc"}))
  end

  describe "PID" do
    feature "client origin", %{session: session} do
      assert_js_error session,
                      "can't encode client terms that are PIDs originating in client",
                      fn ->
                        session
                        |> visit(TypesPage)
                        |> click(css("button[id='pid (client origin)']"))
                      end
    end

    feature "server origin", %{session: session} do
      session
      |> visit(TypesPage)
      |> click(css("button[id='pid (server origin)']"))
      |> assert_text(css("#result"), inspect(pid("0.11.222")))
    end
  end

  feature "tuple", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='tuple']"))
    |> assert_text(css("#result"), inspect({123, :abc}))
  end
end
