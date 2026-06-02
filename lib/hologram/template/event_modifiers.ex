defmodule Hologram.Template.EventModifiers do
  @moduledoc false

  alias Hologram.TemplateSyntaxError

  # Unshifted printable symbol keys, written as alias words (never raw). Names are the
  # snake-cased DOM event.code, so each resolves to the matched (unshifted) event.key char.
  @char_by_alias %{
    "backquote" => "`",
    "backslash" => "\\",
    "bracket_left" => "[",
    "bracket_right" => "]",
    "comma" => ",",
    "equal" => "=",
    "minus" => "-",
    "period" => ".",
    "quote" => "'",
    "semicolon" => ";",
    "slash" => "/",
    "space" => " "
  }

  # Reverse map (char -> alias name), used to suggest the alias when a raw symbol is written.
  @alias_by_char Map.new(@char_by_alias, fn {name, char} -> {char, name} end)

  # Event attribute base names that carry keyboard key filters.
  @keyboard_events ["$key_down", "$key_up"]

  # Modifier keys are matched against the event's boolean flags (event.ctrlKey,
  # event.altKey, etc.) rather than against event.key.
  @modifier_keys ~w(alt ctrl meta shift)

  # Named multi-character keys, snake-cased from the browser's event.key
  # (`ArrowDown` -> `"arrow_down"`). These readable names are what the developer writes - they
  # drive validation and did-you-mean. The string the matcher compares against, though, is the
  # normalized form: underscores stripped so it equals `event.key.toLowerCase()`
  # (`"arrow_down"` -> `"arrowdown"`), so matching is a plain equality against event.key.
  @named_keys ~w(
                  arrow_down arrow_left arrow_right arrow_up
                  backspace caps_lock delete end enter escape
                  home insert page_down page_up tab
                ) ++ for(n <- 1..12, do: "f#{n}")

  @doc """
  Returns true if the given event attribute base name carries keyboard key filters.
  """
  @spec keyboard_event?(String.t()) :: boolean
  def keyboard_event?(base_name), do: base_name in @keyboard_events

  @doc """
  Parses the raw modifier segments of a keyboard event attribute into tagged key filters.

  Each segment becomes a `{:key, values}` tuple holding the resolved modifier flags and the
  single matched key. Raises `Hologram.TemplateSyntaxError` for an empty segment, an unknown
  multi-character key, or more than one key in a single filter.
  """
  @spec parse(list(String.t())) :: list({:key, list(String.t())})
  def parse(segments), do: Enum.map(segments, &parse_segment/1)

  defp did_you_mean(name) do
    candidates = @modifier_keys ++ @named_keys ++ Map.keys(@char_by_alias)
    best = Enum.max_by(candidates, &String.jaro_distance(name, &1))

    if String.jaro_distance(name, best) >= 0.75 do
      ~s'Did you mean "#{best}"?'
    else
      ""
    end
  end

  defp parse_segment(segment) do
    values =
      segment
      |> String.split("+")
      |> Enum.map(&parse_token/1)

    if Enum.count(values, &(&1 not in @modifier_keys)) > 1 do
      raise TemplateSyntaxError,
        message: ~s'keyboard key filter "#{segment}" specifies more than one key'
    end

    {:key, values}
  end

  defp parse_token("") do
    raise TemplateSyntaxError, message: "keyboard key filter must not be empty"
  end

  # Single-character token - the common case (a letter/digit key). A letter or digit is the
  # literal key, matched against event.key; a raw symbol must use its alias (or, for a shifted
  # char that has no alias, the action handler).
  defp parse_token(<<_codepoint::utf8>> = token) do
    char = String.downcase(token)

    if String.match?(char, ~r/^[\p{L}\p{N}]$/u) do
      char
    else
      raise TemplateSyntaxError, message: raw_symbol_message(char)
    end
  end

  # Multi-character token: a modifier key, a symbol alias, or a named key.
  defp parse_token(token) do
    name = String.downcase(token)

    cond do
      name in @modifier_keys ->
        name

      # Symbol-key alias resolves to its (unshifted) event.key char.
      Map.has_key?(@char_by_alias, name) ->
        @char_by_alias[name]

      # Canonical event.key form: snake-case separators stripped at compile so the client
      # matcher is a plain equality (`arrow_down` -> `"arrowdown"`).
      name in @named_keys ->
        String.replace(name, "_", "")

      true ->
        raise TemplateSyntaxError,
          message: ~s'unknown keyboard key "#{token}". #{did_you_mean(name)}'
    end
  end

  defp raw_symbol_message(char) do
    case Map.fetch(@alias_by_char, char) do
      {:ok, name} ->
        ~s'use "#{name}" instead of the literal "#{char}" in a keyboard key filter'

      :error ->
        ~s'the "#{char}" key has no keyboard key filter alias; match it in the action handler'
    end
  end
end
