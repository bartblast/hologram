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

  # A debounce modifier segment: "debounce(<digits>)". The captured group is validated as a
  # positive integer separately, so the error message can name the offending segment.
  @debounce_regex ~r/^debounce\((.*)\)$/

  # Milliseconds applied by the bare "debounce" segment (no parentheses). A general-purpose
  # default in the conventional 200-300ms range, long enough to coalesce a burst of events and
  # short enough to stay responsive once they settle. High-frequency events usually pass an
  # explicit, smaller value.
  @default_debounce_ms 250

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

  @typedoc """
  A parsed event modifier: a keyboard key filter, a debounce window in milliseconds, or an
  opt-out of the framework's default preventDefault.
  """
  @type modifier :: {:allow_default} | {:debounce, pos_integer} | {:key, list(String.t())}

  @doc """
  Returns true if the given event attribute base name carries keyboard key filters.
  """
  @spec keyboard_event?(String.t()) :: boolean
  def keyboard_event?(base_name), do: base_name in @keyboard_events

  @doc """
  Parses the raw modifier segments of an event attribute into tagged modifiers.

  `base_name` is the event's bare name (e.g. `"$key_down"`) and decides which modifiers a
  segment may be. A `debounce(ms)` segment becomes `{:debounce, ms}` and an `allow_default`
  segment becomes `{:allow_default}` - both are valid on any event. A keyboard key filter becomes
  a `{:key, values}` tuple holding the resolved modifier flags and the single matched key, and is
  valid only on keyboard events.

  Raises `Hologram.TemplateSyntaxError` for a debounce value that is not a positive integer, a
  key filter on a non-keyboard event, an empty segment, an unknown key, more than one key in a
  single filter, or more than one debounce modifier.
  """
  @spec parse(String.t(), list(String.t())) :: list(modifier)
  def parse(base_name, segments) do
    segments
    |> Enum.map(&parse_segment(base_name, &1))
    |> validate_single_debounce()
  end

  defp debounce_error(segment) do
    ~s'debounce modifier "#{segment}" requires a positive integer of milliseconds'
  end

  defp did_you_mean(name) do
    candidates = @modifier_keys ++ @named_keys ++ Map.keys(@char_by_alias)
    best = Enum.max_by(candidates, &String.jaro_distance(name, &1))

    if String.jaro_distance(name, best) >= 0.75 do
      ~s'Did you mean "#{best}"?'
    else
      ""
    end
  end

  defp parse_debounce_value(segment, value) do
    case Integer.parse(value) do
      {ms, ""} when ms > 0 -> {:debounce, ms}
      _fallback -> raise TemplateSyntaxError, message: debounce_error(segment)
    end
  end

  # Key filters are valid only on keyboard events.
  defp parse_key_filter(base_name, segment) do
    if keyboard_event?(base_name) do
      parse_keyboard_segment(segment)
    else
      raise TemplateSyntaxError, message: ~s'unknown event modifier "#{segment}"'
    end
  end

  defp parse_keyboard_segment(segment) do
    values =
      segment
      |> String.split("+")
      |> Enum.map(&parse_token/1)

    case Enum.count(values, &(&1 not in @modifier_keys)) do
      1 ->
        {:key, values}

      0 ->
        raise TemplateSyntaxError,
          message: ~s'keyboard key filter "#{segment}" specifies no key'

      _count ->
        raise TemplateSyntaxError,
          message: ~s'keyboard key filter "#{segment}" specifies more than one key'
    end
  end

  defp parse_segment(base_name, segment) do
    case parse_universal_modifier(segment) do
      :error -> parse_key_filter(base_name, segment)
      modifier -> modifier
    end
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

  # Universal modifiers are valid on any event.
  defp parse_universal_modifier(segment)

  defp parse_universal_modifier("allow_default"), do: {:allow_default}

  defp parse_universal_modifier("debounce"), do: {:debounce, @default_debounce_ms}

  defp parse_universal_modifier(segment) do
    case Regex.run(@debounce_regex, segment) do
      [_match, value] ->
        parse_debounce_value(segment, value)

      nil ->
        if String.starts_with?(segment, "debounce") do
          raise TemplateSyntaxError, message: debounce_error(segment)
        else
          :error
        end
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

  # An event binding has a single debounce window and the client reads only the first debounce
  # modifier, so more than one would silently drop the rest. Fail the build instead.
  defp validate_single_debounce(modifiers) do
    if Enum.count(modifiers, &match?({:debounce, _ms}, &1)) > 1 do
      raise TemplateSyntaxError,
        message: "an event binding may include at most one debounce modifier"
    end

    modifiers
  end
end
