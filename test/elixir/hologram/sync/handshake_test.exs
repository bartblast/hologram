defmodule Hologram.Sync.HandshakeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.Handshake

  alias Hologram.Entity.Model
  alias Hologram.Sync.Frame

  defp greeting(overrides \\ %{}) do
    Map.merge(
      %{
        model_hash: Model.hash(),
        page: MyApp.BoardPage,
        protocol_version: Frame.protocol_version()
      },
      overrides
    )
  end

  describe "check/1" do
    test "serves a client speaking this build's protocol and model" do
      assert check(greeting()) == {:sync, MyApp.BoardPage}
    end

    test "takes the page the client names at face value" do
      assert check(greeting(%{page: MyApp.SomeOtherPage})) == {:sync, MyApp.SomeOtherPage}
    end

    test "reloads a client speaking another protocol version" do
      assert check(greeting(%{protocol_version: Frame.protocol_version() + 1})) ==
               {:reload, :protocol_version}
    end

    test "reloads a client built against another model" do
      assert check(greeting(%{model_hash: "a3f9c2"})) == {:reload, :model_hash}
    end

    # The protocol decides how the rest of the greeting is even spelled, so a version this build
    # does not speak is answered before anything else in it is believed.
    test "reloads on the protocol version before looking at the model" do
      disagreeing = greeting(%{model_hash: "a3f9c2", protocol_version: 99})

      assert check(disagreeing) == {:reload, :protocol_version}
    end

    test "leaves a client that said nothing about sync alone" do
      assert check(%{}) == :no_sync
    end

    test "leaves a client that said only part of it alone" do
      assert check(%{page: MyApp.BoardPage}) == :no_sync
    end
  end
end
