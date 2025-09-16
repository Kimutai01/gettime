# Gettime

[![Hex.pm Version](https://img.shields.io/hexpm/v/gettime.svg)](https://hex.pm/packages/gettime)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/gettime)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A powerful and flexible Elixir library for converting database timestamps to user-specific timezones with configurable formatting. Inspired by the simplicity of `gettext`, Gettime provides seamless timezone conversion for Phoenix applications and APIs.

## Why Gettime?

- **Multiple Input Formats**: Handles `DateTime`, `NaiveDateTime`, Unix timestamps, ISO8601, RFC3339, and common date strings
- **Configurable Defaults**: Set application-wide timezone and format preferences
- **Custom Format Support**: Add your own timestamp parsing patterns via config or at runtime  
- **Batch Processing**: Convert multiple timestamps efficiently in one operation
- **Zero External APIs**: Uses Elixir's built-in `tzdata` - works offline
- **Phoenix Integration**: Designed for Phoenix controllers, LiveView, and contexts
- **Comprehensive Error Handling**: Clear error messages for debugging

## Installation

Add `gettime` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gettime, "~> 0.1.0"}
  ]
end
```

Then run:
```bash
mix deps.get
```

## Configuration

Add to your `config/config.exs`:

```elixir
# REQUIRED: Configure Elixir to use tzdata as the timezone database
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :gettime,
  default_db_timezone: "UTC",                    # Your database timezone
  default_user_timezone: "America/New_York",     # Default user timezone  
  default_format: "%Y-%m-%d %H:%M:%S %Z",        # Default output format
  # Optional: Custom input formats for parsing unusual timestamp strings
  custom_input_formats: [
    {~r/^(\d{4})\.(\d{2})\.(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$/, :parse_dot_format},
    {~r/^(\d{2})-(\d{2})-(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$/, :parse_dmy_format}
  ]
```

## Quick Start

```elixir
# Basic conversion with defaults
{:ok, result} = Gettime.convert(~N[2024-01-15 14:30:00])
# => {:ok, "2024-01-15 09:30:00 EST"}

# Convert to specific timezone
{:ok, result} = Gettime.convert(~N[2024-01-15 14:30:00], "Europe/London")  
# => {:ok, "2024-01-15 14:30:00 GMT"}

# Custom format
{:ok, result} = Gettime.convert(
  ~N[2024-01-15 14:30:00], 
  "Asia/Tokyo", 
  "%B %d, %Y at %I:%M %p"
)
# => {:ok, "January 15, 2024 at 11:30 PM"}
```

## Supported Input Formats

Gettime automatically detects and parses these timestamp formats:

### Native Elixir Types
- **`DateTime`** - `%DateTime{}`
- **`NaiveDateTime`** - `~N[2024-01-15 14:30:00]`  
- **`Date`** - `~D[2024-01-15]` (converts to midnight)

### Unix Timestamps
- **Integer** - `1705330200`
- **Float** - `1705330200.123`

### ISO Standards
- **ISO8601 with timezone** - `"2024-01-15T14:30:00Z"`
- **ISO8601 with offset** - `"2024-01-15T14:30:00+00:00"`
- **ISO8601 without timezone** - `"2024-01-15T14:30:00"`
- **Date only** - `"2024-01-15"`

### Common Date Strings
- **Standard format** - `"2024-01-15 14:30:00"`
- **US format** - `"01/15/2024 14:30:00"`
- **EU format** - `"15/01/2024 14:30:00"`

## API Reference

### Core Functions

#### `convert/3`
Converts a single timestamp to the target timezone.

```elixir
@spec convert(timestamp, timezone | nil, format | nil) :: {:ok, String.t()} | {:error, term}
```

**Parameters:**
- `timestamp` - Any supported timestamp format
- `timezone` - Target timezone (optional, uses config default)
- `format` - Output format string (optional, uses config default)

**Examples:**
```elixir
# Different input types
Gettime.convert(~N[2024-01-15 14:30:00], "Europe/Paris")
Gettime.convert("2024-01-15T14:30:00Z", "Asia/Tokyo")
Gettime.convert(1705330200, "America/Los_Angeles")

# Custom formatting
Gettime.convert(~N[2024-01-15 14:30:00], "UTC", "%Y-%m-%d")
# => {:ok, "2024-01-15"}

Gettime.convert(~N[2024-01-15 14:30:00], "America/New_York", "%B %d, %Y at %I:%M %p %Z")
# => {:ok, "January 15, 2024 at 09:30 AM EST"}
```

#### `convert_batch/3`
Efficiently converts multiple timestamps at once.

```elixir
@spec convert_batch([timestamp], timezone | nil, format | nil) :: {:ok, [String.t()]} | {:error, term}
```

**Example:**
```elixir
timestamps = [
  ~N[2024-01-15 14:30:00],
  "2024-01-15T15:45:00Z",
  1705334100
]

{:ok, results} = Gettime.convert_batch(timestamps, "America/Chicago")
# => {:ok, ["2024-01-15 08:30:00 CST", "2024-01-15 09:45:00 CST", "2024-01-15 09:55:00 CST"]}
```

### Utility Functions

#### `available_timezones/0`
Returns list of all available timezone identifiers.

```elixir
timezones = Gettime.available_timezones()
# => ["Africa/Abidjan", "Africa/Accra", ...]
```

#### `valid_timezone?/1`
Validates if a timezone identifier is valid.

```elixir
Gettime.valid_timezone?("America/New_York")  # => true
Gettime.valid_timezone?("Invalid/Zone")      # => false
```

### Custom Format Support

#### `add_custom_format/2`
Add custom timestamp parsing patterns at runtime.

```elixir
# Parser function that returns {:ok, DateTime/NaiveDateTime/Date} or {:error, reason}
custom_parser = fn timestamp_string, regex ->
  case Regex.run(regex, timestamp_string) do
    [_, year, month, day] ->
      Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day))
    _ -> 
      {:error, :invalid_format}
  end
end

# Add the custom format
Gettime.add_custom_format(~r/^(\d{4})\|(\d{2})\|(\d{2})$/, custom_parser)

# Now you can use it
{:ok, result} = Gettime.convert("2024|01|15", "UTC")
# => {:ok, "2024-01-15 00:00:00 UTC"}
```

## Output Format Strings

Gettime uses Elixir's `Calendar.strftime/2` for formatting. Common patterns:

| Pattern | Description | Example |
|---------|-------------|---------|
| `%Y` | 4-digit year | `2024` |
| `%m` | Month (01-12) | `01` |  
| `%d` | Day (01-31) | `15` |
| `%H` | Hour 24-hour (00-23) | `14` |
| `%I` | Hour 12-hour (01-12) | `02` |
| `%M` | Minute (00-59) | `30` |
| `%S` | Second (00-59) | `00` |
| `%p` | AM/PM | `PM` |
| `%Z` | Timezone abbreviation | `EST` |
| `%B` | Full month name | `January` |
| `%b` | Abbreviated month | `Jan` |

**Common format examples:**
```elixir
# US format
"%m/%d/%Y %I:%M %p"           # => "01/15/2024 09:30 AM"

# ISO format  
"%Y-%m-%dT%H:%M:%S%z"         # => "2024-01-15T09:30:00-0500"

# Readable format
"%B %d, %Y at %I:%M %p %Z"    # => "January 15, 2024 at 09:30 AM EST"

# Date only
"%Y-%m-%d"                    # => "2024-01-15"
```

## Phoenix Integration

### Controllers

```elixir
defmodule MyAppWeb.PostController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    posts = Blog.list_posts()
    user_timezone = get_user_timezone(conn)
    
    formatted_posts = Enum.map(posts, fn post ->
      {:ok, display_date} = Gettime.convert(post.inserted_at, user_timezone, "%B %d, %Y")
      Map.put(post, :display_date, display_date)
    end)
    
    render(conn, :index, posts: formatted_posts)
  end
  
  defp get_user_timezone(conn) do
    # Get from user session, preferences, or IP geolocation
    get_session(conn, :timezone) || "UTC"
  end
end
```

### LiveView

```elixir
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view

  def mount(_params, session, socket) do
    user_timezone = session["user_timezone"] || "UTC"
    current_time_str = case Gettime.convert(DateTime.utc_now(), user_timezone) do
      {:ok, time} -> time
      {:error, _} -> "Invalid timezone"
    end
    
    socket = 
      socket
      |> assign(:user_timezone, user_timezone)
      |> assign(:current_time, current_time_str)
    
    {:ok, socket}
  end

  def handle_event("change_timezone", %{"timezone" => tz}, socket) do
    if Gettime.valid_timezone?(tz) do
      {:ok, current_time} = Gettime.convert(DateTime.utc_now(), tz)
      
      socket = 
        socket
        |> assign(:user_timezone, tz)  
        |> assign(:current_time, current_time)
      
      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Invalid timezone")}
    end
  end
end
```

## Error Handling

Gettime provides detailed error information for debugging:

```elixir
case Gettime.convert("invalid-timestamp", "UTC") do
  {:ok, result} -> 
    result
  {:error, {:unparseable_timestamp, timestamp}} -> 
    "Could not parse: #{timestamp}"
  {:error, {:invalid_timezone, tz}} -> 
    "Invalid timezone: #{tz}"
  {:error, {:datetime_conversion_failed, reason}} -> 
    "Conversion failed: #{inspect(reason)}"
end
```

**Common error types:**
- `{:unparseable_timestamp, string}` - Input string couldn't be parsed
- `{:invalid_timezone, timezone}` - Invalid timezone identifier
- `{:datetime_conversion_failed, reason}` - Timezone conversion failed
- `{:formatting_failed, error}` - Output formatting failed
- `:unsupported_timestamp_format` - Input type not supported

## Performance Considerations

### Batch Operations
Use `convert_batch/3` for multiple timestamps - it's more efficient than individual conversions:

```elixir
# Good - single batch operation
{:ok, results} = Gettime.convert_batch(timestamps, timezone)

# Less efficient - multiple individual calls  
results = Enum.map(timestamps, &Gettime.convert(&1, timezone))
```

### Timezone Validation
Cache timezone validation results when processing many records:

```elixir
def convert_with_cached_validation(timestamp, timezone) do
  if valid_timezone_cache(timezone) do
    Gettime.convert(timestamp, timezone)
  else
    {:error, {:invalid_timezone, timezone}}
  end
end
```

### Default Configuration
Set sensible application defaults to minimize parameter passing:

```elixir
# Configure once
config :gettime,
  default_user_timezone: get_app_default_timezone(),
  default_format: get_app_default_format()

# Use throughout app  
Gettime.convert(timestamp)  # Uses configured defaults
```

## Testing

Test timezone conversions in your applications:

```elixir
defmodule MyAppTest do
  use ExUnit.Case
  
  test "converts user timestamps correctly" do
    # Test with known timestamp and timezone
    input = ~N[2024-01-15 14:30:00]
    
    assert {:ok, "2024-01-15 09:30:00 EST"} = 
      Gettime.convert(input, "America/New_York")
      
    assert {:ok, "2024-01-15 23:30:00 JST"} = 
      Gettime.convert(input, "Asia/Tokyo")
  end
  
  test "handles invalid inputs gracefully" do
    assert {:error, {:unparseable_timestamp, "invalid"}} = 
      Gettime.convert("invalid", "UTC")
      
    assert {:error, {:invalid_timezone, "Invalid/Zone"}} = 
      Gettime.convert(~N[2024-01-15 14:30:00], "Invalid/Zone")
  end
end
```

## Troubleshooting

### Debug Mode

Enable debug logging to troubleshoot parsing issues:

```elixir
# In config/dev.exs
config :logger, level: :debug

# Check what format is being attempted
case Gettime.convert("unusual-format", "UTC") do
  {:error, {:unparseable_timestamp, input}} ->
    IO.puts("Could not parse: #{inspect(input)}")
    # Try adding a custom format for this pattern
end
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b my-new-feature`)
3. Make your changes with tests
4. Run the test suite (`mix test`)
5. Run the formatter (`mix format`)
6. Submit a pull request

## License

MIT License. See [LICENSE](LICENSE) for details.

## Changelog

### v0.1.0
- Initial release
- Support for multiple timestamp formats
- Configurable defaults
- Custom format support
- Batch conversion
- Comprehensive error handling