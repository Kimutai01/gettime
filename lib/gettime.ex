defmodule Gettime do
  @moduledoc """
  Gettime provides simple timezone conversion utilities for converting
  database timestamps to user-specific timezones with configurable formatting.
  """

  @doc """
  Converts a timestamp from database timezone to user timezone.

  ## Parameters

    * `timestamp` - A `DateTime`, `NaiveDateTime`, Unix timestamp, or ISO8601/RFC3339 string
    * `user_timezone` - Target timezone (optional, uses config default)
    * `format` - Strftime format string (optional, uses config default)

  ## Supported Input Formats

    * `DateTime` - `%DateTime{}`
    * `NaiveDateTime` - `~N[2024-01-15 14:30:00]`
    * Unix timestamp (integer) - `1705330200`
    * Unix timestamp (float) - `1705330200.123`
    * ISO8601 string - `"2024-01-15T14:30:00Z"`
    * RFC3339 string - `"2024-01-15T14:30:00+00:00"`
    * Date string - `"2024-01-15"`
    * Common datetime strings:
      - `"2024-01-15 14:30:00"`
      - `"01/15/2024 14:30:00"` (US format)
      - `"15/01/2024 14:30:00"` (EU format)
      - `"2024-01-15T14:30:00"`

  ## Returns

    * `{:ok, formatted_string}` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> Gettime.convert(~N[2024-01-15 14:30:00])
      {:ok, "2024-01-15 09:30:00 EST"}

      iex> Gettime.convert("2024-01-15T14:30:00Z", "America/Los_Angeles")
      {:ok, "2024-01-15 06:30:00 PST"}

      iex> Gettime.convert(1705330200, "Europe/London")
      {:ok, "2024-01-15 14:30:00 GMT"}

      iex> Gettime.convert("01/15/2024 14:30:00", "Asia/Tokyo", "%B %d, %Y at %I:%M %p")
      {:ok, "January 15, 2024 at 11:30 PM"}
  """
  def convert(timestamp, user_timezone \\ nil, format \\ nil) do
    with {:ok, db_timezone} <- get_db_timezone(),
         {:ok, target_timezone} <- get_user_timezone(user_timezone),
         {:ok, format_string} <- get_format(format),
         {:ok, datetime} <- normalize_timestamp(timestamp, db_timezone),
         {:ok, converted_datetime} <- convert_timezone(datetime, target_timezone),
         {:ok, formatted} <- format_datetime(converted_datetime, format_string) do
      {:ok, formatted}
    else
      error -> error
    end
  end

  @doc """
  Converts multiple timestamps in batch.

  ## Parameters

    * `timestamps` - List of timestamps
    * `user_timezone` - Target timezone (optional)
    * `format` - Format string (optional)

  ## Returns

    * `{:ok, [formatted_strings]}` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> timestamps = [~N[2024-01-15 14:30:00], ~N[2024-01-15 15:45:00]]
      iex> Gettime.convert_batch(timestamps, "Europe/Paris")
      {:ok, ["2024-01-15 15:30:00 CET", "2024-01-15 16:45:00 CET"]}
  """
  def convert_batch(timestamps, user_timezone \\ nil, format \\ nil) when is_list(timestamps) do
    results = Enum.map(timestamps, &convert(&1, user_timezone, format))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        converted = Enum.map(results, fn {:ok, result} -> result end)
        {:ok, converted}

      error ->
        error
    end
  end

  @doc """
  Adds a custom input format parser at runtime.

  ## Parameters

    * `regex` - A regex pattern to match the timestamp format
    * `parser_fun` - A function that takes (timestamp_string, regex) and returns {:ok, datetime} or {:error, reason}

  ## Examples

      # Add support for "2024.01.15 14:30:00" format
      custom_parser = fn timestamp, regex ->
        case Regex.run(regex, timestamp) do
          [_, year, month, day, hour, minute, second] ->
            # Parse and return NaiveDateTime
            NaiveDateTime.new(String.to_integer(year), String.to_integer(month),
                             String.to_integer(day), String.to_integer(hour),
                             String.to_integer(minute), String.to_integer(second))
          _ -> {:error, :invalid_format}
        end
      end

      Gettime.add_custom_format(~r/^(\d{4})\.(\d{2})\.(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$/, custom_parser)
  """
  def add_custom_format(regex, parser_fun)
      when is_struct(regex, Regex) and is_function(parser_fun, 2) do
    current_formats = Application.get_env(:gettime, :custom_input_formats, [])
    new_formats = [{regex, parser_fun} | current_formats]
    Application.put_env(:gettime, :custom_input_formats, new_formats)
    :ok
  end

  @doc """
  Gets available timezones.

  ## Examples

      iex> Gettime.available_timezones() |> Enum.take(3)
      ["Africa/Abidjan", "Africa/Accra", "Africa/Addis_Ababa"]
  """
  def available_timezones do
    Tzdata.zone_list()
  end

  @doc """
  Validates if a timezone is valid.

  ## Examples

      iex> Gettime.valid_timezone?("America/New_York")
      true

      iex> Gettime.valid_timezone?("Invalid/Timezone")
      false
  """
  def valid_timezone?(timezone) when is_binary(timezone) do
    timezone in available_timezones()
  end


  defp get_db_timezone do
    case Application.get_env(:gettime, :default_db_timezone, "UTC") do
      timezone when is_binary(timezone) -> {:ok, timezone}
      _ -> {:error, :invalid_db_timezone_config}
    end
  end

  defp get_user_timezone(nil) do
    case Application.get_env(:gettime, :default_user_timezone, "UTC") do
      timezone when is_binary(timezone) ->
        if valid_timezone?(timezone) do
          {:ok, timezone}
        else
          {:error, {:invalid_timezone, timezone}}
        end

      _ ->
        {:error, :invalid_user_timezone_config}
    end
  end

  defp get_user_timezone(timezone) when is_binary(timezone) do
    if valid_timezone?(timezone) do
      {:ok, timezone}
    else
      {:error, {:invalid_timezone, timezone}}
    end
  end

  defp get_format(nil) do
    {:ok, Application.get_env(:gettime, :default_format, "%Y-%m-%d %H:%M:%S %Z")}
  end

  defp get_format(format) when is_binary(format), do: {:ok, format}

  defp normalize_timestamp(%DateTime{} = datetime, _db_timezone) do
    {:ok, datetime}
  end

  defp normalize_timestamp(%NaiveDateTime{} = naive_datetime, db_timezone) do
    case DateTime.from_naive(naive_datetime, db_timezone) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, reason} -> {:error, {:datetime_conversion_failed, reason}}
    end
  end

  defp normalize_timestamp(unix_timestamp, _db_timezone) when is_integer(unix_timestamp) do
    case DateTime.from_unix(unix_timestamp) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, reason} -> {:error, {:unix_conversion_failed, reason}}
    end
  end

  defp normalize_timestamp(unix_timestamp, _db_timezone) when is_float(unix_timestamp) do
    case DateTime.from_unix(trunc(unix_timestamp)) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, reason} -> {:error, {:unix_conversion_failed, reason}}
    end
  end

  defp normalize_timestamp(%Date{} = date, db_timezone) do
    naive_datetime = DateTime.new!(date, ~T[00:00:00])

    case DateTime.from_naive(naive_datetime, db_timezone) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, reason} -> {:error, {:date_conversion_failed, reason}}
    end
  end

  defp normalize_timestamp(timestamp_string, db_timezone) when is_binary(timestamp_string) do
    parse_string_timestamp(timestamp_string, db_timezone)
  end

  defp normalize_timestamp(_, _) do
    {:error, :unsupported_timestamp_format}
  end

  # Parse various string timestamp formats
  defp parse_string_timestamp(timestamp_string, db_timezone) do
    timestamp_string
    |> String.trim()
    |> try_parse_formats(db_timezone)
  end

  defp try_parse_formats(timestamp_string, db_timezone) do
    # Get built-in parsers
    builtin_parsers = [
      &parse_iso8601/1,
      &parse_rfc3339/1,
      &parse_date_only/1,
      &parse_standard_datetime/1,
      &parse_us_datetime/1,
      &parse_eu_datetime/1,
      &parse_iso_datetime/1
    ]

    # Get custom parsers from config
    custom_parsers = get_custom_parsers(timestamp_string)

    # Try custom parsers first, then built-in parsers
    all_parsers = custom_parsers ++ builtin_parsers

    case try_parsers(timestamp_string, all_parsers, db_timezone) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, _} -> {:error, {:unparseable_timestamp, timestamp_string}}
    end
  end

  defp get_custom_parsers(timestamp_string) do
    case Application.get_env(:gettime, :custom_input_formats, []) do
      formats when is_list(formats) ->
        formats
        |> Enum.filter(fn
          {regex, _parser} when is_struct(regex, Regex) -> Regex.match?(regex, timestamp_string)
          _ -> false
        end)
        |> Enum.map(fn
          {regex, parser_name} when is_atom(parser_name) ->
            fn ts -> apply(__MODULE__, parser_name, [ts, regex]) end

          {regex, parser_fun} when is_function(parser_fun, 2) ->
            fn ts -> parser_fun.(ts, regex) end

          _ ->
            fn _ts -> {:error, :invalid_custom_parser} end
        end)

      _ ->
        []
    end
  end

  # Custom parser functions that users can reference in config
  def parse_dot_format(timestamp_string, regex) do
    case Regex.run(regex, timestamp_string) do
      [_, year, month, day, hour, minute, second] ->
        with {year, ""} <- Integer.parse(year),
             {month, ""} <- Integer.parse(month),
             {day, ""} <- Integer.parse(day),
             {hour, ""} <- Integer.parse(hour),
             {minute, ""} <- Integer.parse(minute),
             {second, ""} <- Integer.parse(second) do
          NaiveDateTime.new(year, month, day, hour, minute, second)
        else
          _ -> {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  def parse_dmy_format(timestamp_string, regex) do
    case Regex.run(regex, timestamp_string) do
      [_, day, month, year, hour, minute, second] ->
        with {year, ""} <- Integer.parse(year),
             {month, ""} <- Integer.parse(month),
             {day, ""} <- Integer.parse(day),
             {hour, ""} <- Integer.parse(hour),
             {minute, ""} <- Integer.parse(minute),
             {second, ""} <- Integer.parse(second) do
          NaiveDateTime.new(year, month, day, hour, minute, second)
        else
          _ -> {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  defp try_parsers(_timestamp_string, [], _db_timezone) do
    {:error, :no_parser_matched}
  end

  defp try_parsers(timestamp_string, [parser | rest], db_timezone) do
    case parser.(timestamp_string) do
      {:ok, result} ->
        case result do
          %DateTime{} = dt ->
            {:ok, dt}

          %NaiveDateTime{} = ndt ->
            DateTime.from_naive(ndt, db_timezone)

          %Date{} = date ->
            naive_datetime = DateTime.new!(date, ~T[00:00:00])
            DateTime.from_naive(naive_datetime, db_timezone)
        end

      {:error, _} ->
        try_parsers(timestamp_string, rest, db_timezone)
    end
  end

  # ISO8601 with timezone: "2024-01-15T14:30:00Z" or "2024-01-15T14:30:00+00:00"
  defp parse_iso8601(timestamp_string) do
    case DateTime.from_iso8601(timestamp_string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      # Handle 2-tuple return
      {:ok, datetime} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  # RFC3339: "2024-01-15T14:30:00+00:00"
  defp parse_rfc3339(timestamp_string) do
    case DateTime.from_iso8601(timestamp_string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      # Handle 2-tuple return
      {:ok, datetime} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  # Date only: "2024-01-15"
  defp parse_date_only(timestamp_string) do
    Date.from_iso8601(timestamp_string)
  end

  # Standard datetime: "2024-01-15 14:30:00"
  defp parse_standard_datetime(timestamp_string) do
    case Regex.run(~r/^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$/, timestamp_string) do
      [_, year, month, day, hour, minute, second] ->
        with {year, ""} <- Integer.parse(year),
             {month, ""} <- Integer.parse(month),
             {day, ""} <- Integer.parse(day),
             {hour, ""} <- Integer.parse(hour),
             {minute, ""} <- Integer.parse(minute),
             {second, ""} <- Integer.parse(second) do
          NaiveDateTime.new(year, month, day, hour, minute, second)
        else
          _ -> {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  # US format: "01/15/2024 14:30:00"
  defp parse_us_datetime(timestamp_string) do
    case Regex.run(~r/^(\d{2})\/(\d{2})\/(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$/, timestamp_string) do
      [_, month, day, year, hour, minute, second] ->
        with {year, ""} <- Integer.parse(year),
             {month, ""} <- Integer.parse(month),
             {day, ""} <- Integer.parse(day),
             {hour, ""} <- Integer.parse(hour),
             {minute, ""} <- Integer.parse(minute),
             {second, ""} <- Integer.parse(second) do
          NaiveDateTime.new(year, month, day, hour, minute, second)
        else
          _ -> {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  # EU format: "15/01/2024 14:30:00"
  defp parse_eu_datetime(timestamp_string) do
    case Regex.run(~r/^(\d{2})\/(\d{2})\/(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$/, timestamp_string) do
      [_, day, month, year, hour, minute, second] ->
        with {year, ""} <- Integer.parse(year),
             {month, ""} <- Integer.parse(month),
             {day, ""} <- Integer.parse(day),
             {hour, ""} <- Integer.parse(hour),
             {minute, ""} <- Integer.parse(minute),
             {second, ""} <- Integer.parse(second) do
          NaiveDateTime.new(year, month, day, hour, minute, second)
        else
          _ -> {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  # ISO datetime without timezone: "2024-01-15T14:30:00"
  defp parse_iso_datetime(timestamp_string) do
    NaiveDateTime.from_iso8601(timestamp_string)
  end

  defp convert_timezone(datetime, target_timezone) do
    case DateTime.shift_zone(datetime, target_timezone) do
      {:ok, converted} -> {:ok, converted}
      {:error, reason} -> {:error, {:timezone_conversion_failed, reason}}
    end
  end

  defp format_datetime(datetime, format) do
    try do
      formatted = Calendar.strftime(datetime, format)
      {:ok, formatted}
    rescue
      error -> {:error, {:formatting_failed, error}}
    end
  end
end
