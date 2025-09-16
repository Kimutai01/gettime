import Config
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :gettime,
  default_db_timezone: "UTC",
  default_user_timezone: "America/New_York",
  default_format: "%Y-%m-%d %H:%M:%S %Z"

import_config "#{config_env()}.exs"
