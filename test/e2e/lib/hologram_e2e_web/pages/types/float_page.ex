defmodule HologramE2E.Types.FloatPage do
  use Hologram.Page

  route "/e2e/types/float"

  def init(_params, _conn) do
    %{
      result_encoding: 0,
      result_decoding: 0
    }
  end

  def template do
    ~H"""
    <button id="button_test_encoding" on:click="test_encoding">Test encoding</button>
    <button id="button_test_decoding" on:click.command={:test_decoding, client_param: 2.34}>Test decoding</button>
    <div id="text_encoding_result">Result encoding = {@result_encoding}</div>
    <div id="text_decoding_result">Result decoding = {@result_decoding}</div>
    """
  end

  def action(:test_encoding, _params, state) do
    Map.put(state, :result_encoding, 1.23)
  end

  def action(:dipslay_test_decoding_result, params, state) do
    Map.put(state, :result_decoding, params.server_result)
  end

  def command(:test_decoding, params) do
    {:dipslay_test_decoding_result, server_result: params.client_param + 10}
  end
end
