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

  # Milliseconds applied by the bare "throttle" segment (no parentheses). A general-purpose max
  # update rate of ~10 dispatches per second: smooth enough to feel live for continuous feedback
  # (cursor, drag, scroll), light enough not to spam the render pipeline. Interactions wanting
  # finer or coarser updates pass an explicit value.
  @default_throttle_ms 100

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

  # Modifier types that may appear at most once on a binding - every type except key filters.
  @single_valued_modifiers ~w(allow_default debounce stop_propagation throttle)a

  # A throttle modifier segment: "throttle(<digits>)". The captured group is validated as a
  # positive integer separately, so the error message can name the offending segment.
  @throttle_regex ~r/^throttle\((.*)\)$/

  @typedoc """
  An event binding's parsed modifiers, keyed by type. Sparse - only the modifiers present on the
  binding appear.
  """
  @type modifiers :: %{
          optional(:allow_default) => true,
          optional(:debounce) => pos_integer,
          optional(:key) => list(list(String.t())),
          optional(:stop_propagation) => true,
          optional(:throttle) => pos_integer
        }

  @typedoc """
  A single parsed modifier in its intermediate tagged form, before aggregation into the map.
  """
  @type tagged_modifier ::
          {:allow_default}
          | {:debounce, pos_integer}
          | {:key, list(String.t())}
          | {:stop_propagation}
          | {:throttle, pos_integer}

  @doc """
  Returns true if the given event attribute base name carries keyboard key filters.
  """
  @spec keyboard_event?(String.t()) :: boolean
  def keyboard_event?(base_name), do: base_name in @keyboard_events

  @doc """
  Parses the raw modifier segments of an event attribute into a map of modifiers keyed by type.

  `base_name` is the event's bare name (e.g. `"$key_down"`) and decides which modifiers a segment
  may be. The map is sparse, holding only the modifiers present on the binding:

    * `:allow_default` - `true` when the binding opts out of the framework's preventDefault, valid
      on any event
    * `:debounce` - the debounce window in milliseconds, valid on any event
    * `:key` - the keyboard key filters as a list, each a list of the resolved modifier flags and
      the single matched key, valid only on keyboard events
    * `:stop_propagation` - `true` when the binding stops the event from propagating past the
      bound element, valid on any event
    * `:throttle` - the throttle window in milliseconds, valid on any event

  Raises `Hologram.TemplateSyntaxError` for a debounce or throttle value that is not a positive
  integer, a key filter on a non-keyboard event, an empty segment, an unknown key, more than one
  key in a single filter, a repeated modifier, two key filters that match the same keys, or a
  binding that combines debounce and throttle.
  """
  @spec parse(String.t(), list(String.t())) :: modifiers
  def parse(base_name, segments) do
    segments
    |> Enum.map(&{&1, parse_segment(base_name, &1)})
    |> validate_modifier_counts()
    |> validate_key_filter_combos()
    |> Enum.map(fn {_segment, modifier} -> modifier end)
    |> aggregate()
  end

  # Collapses the tagged modifier list into a map keyed by type. Key filters accumulate under
  # :key (several may apply), while the remaining modifiers are single-valued.
  defp aggregate(modifiers) do
    modifiers
    |> Enum.reduce(%{}, fn
      {:key, values}, acc -> Map.update(acc, :key, [values], &[values | &1])
      {:debounce, ms}, acc -> Map.put(acc, :debounce, ms)
      {:throttle, ms}, acc -> Map.put(acc, :throttle, ms)
      {:stop_propagation}, acc -> Map.put(acc, :stop_propagation, true)
      {:allow_default}, acc -> Map.put(acc, :allow_default, true)
    end)
    |> reverse_key_filters()
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

  defp parse_throttle_value(segment, value) do
    case Integer.parse(value) do
      {ms, ""} when ms > 0 -> {:throttle, ms}
      _fallback -> raise TemplateSyntaxError, message: throttle_error(segment)
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

  defp parse_universal_modifier("stop_propagation"), do: {:stop_propagation}

  defp parse_universal_modifier("throttle"), do: {:throttle, @default_throttle_ms}

  defp parse_universal_modifier(segment) do
    cond do
      captures = Regex.run(@debounce_regex, segment) ->
        parse_debounce_value(segment, List.last(captures))

      captures = Regex.run(@throttle_regex, segment) ->
        parse_throttle_value(segment, List.last(captures))

      String.starts_with?(segment, "debounce") ->
        raise TemplateSyntaxError, message: debounce_error(segment)

      String.starts_with?(segment, "throttle") ->
        raise TemplateSyntaxError, message: throttle_error(segment)

      true ->
        :error
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

  # Key filters are prepended during aggregation, so restore their written order.
  defp reverse_key_filters(modifiers)

  defp reverse_key_filters(%{key: filters} = modifiers) do
    %{modifiers | key: Enum.reverse(filters)}
  end

  defp reverse_key_filters(modifiers), do: modifiers

  defp throttle_error(segment) do
    ~s'throttle modifier "#{segment}" requires a positive integer of milliseconds'
  end

  # Key filters may repeat, but two filters resolving to the same modifier flags and key (e.g.
  # "ctrl+shift+k" and "shift+ctrl+k") match exactly the same events, so the duplicate is always
  # an authoring mistake. The client matches resolved values order-insensitively, hence the sorted
  # comparison. Fail the build, naming the written segments.
  defp validate_key_filter_combos(pairs) do
    pairs
    |> Enum.filter(fn {_segment, modifier} -> match?({:key, _values}, modifier) end)
    |> Enum.reduce(%{}, fn {segment, {:key, values}}, seen ->
      combo = Enum.sort(values)

      case seen do
        %{^combo => ^segment} ->
          raise TemplateSyntaxError, message: ~s'keyboard key filter "#{segment}" is repeated'

        %{^combo => other_segment} ->
          raise TemplateSyntaxError,
            message:
              ~s'keyboard key filters "#{other_segment}" and "#{segment}" match the same keys'

        _seen ->
          Map.put(seen, combo, segment)
      end
    end)

    pairs
  end

  # Every modifier type except key filters is single-valued, so a duplicate is always an authoring
  # mistake. Debounce and throttle additionally never combine - the two are contradictory (wait
  # for quiet vs fire at a steady rate). Fail the build otherwise.
  defp validate_modifier_counts(pairs) do
    type_counts = Enum.frequencies_by(pairs, fn {_segment, modifier} -> elem(modifier, 0) end)

    Enum.each(@single_valued_modifiers, fn type ->
      if Map.get(type_counts, type, 0) > 1 do
        raise TemplateSyntaxError,
          message: "an event binding may include at most one #{type} modifier"
      end
    end)

    if Map.has_key?(type_counts, :debounce) and Map.has_key?(type_counts, :throttle) do
      raise TemplateSyntaxError,
        message: "an event binding may not combine debounce and throttle modifiers"
    end

    pairs
  end
end
