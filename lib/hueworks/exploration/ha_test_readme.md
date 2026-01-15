# Home Assistant WebSocket API Test

Quick throwaway module to test Home Assistant light control via WebSocket API.

## Setup

1. **Add WebSockex dependency** (already done in mix.exs)

2. **Get your Home Assistant IP address**
   - Find your HA instance IP (e.g., `192.168.1.100`)

3. **Create a long-lived access token**
   - Go to Home Assistant → Profile (click your name) → Long-Lived Access Tokens
   - Click "Create Token"
   - Give it a name like "HueWorks Test"
   - Copy the token (you won't see it again!)

## Usage in IEx

Start your app:
```bash
iex -S mix
```

### Quick Test
```elixir
# Update test() function in ha_test.ex with your host and token, then:
Hueworks.Exploration.HATest.test()
```

### Manual Usage
```elixir
# Connect
{:ok, pid} = Hueworks.Exploration.HATest.connect("192.168.1.100", "your-token-here")

# List all lights
lights = Hueworks.Exploration.HATest.list_lights(pid)

# Get state of a specific light
state = Hueworks.Exploration.HATest.get_state(pid, "light.living_room")

# Turn on a light
Hueworks.Exploration.HATest.turn_on(pid, "light.living_room", brightness: 255)

# Turn on with RGB color (for color-capable lights)
Hueworks.Exploration.HATest.turn_on(pid, "light.strip", brightness: 200, rgb_color: [255, 0, 0])

# Turn off a light
Hueworks.Exploration.HATest.turn_off(pid, "light.living_room")
```

## Available Options for turn_on/3

- `brightness: 0-255` - Light brightness
- `rgb_color: [r, g, b]` - RGB color (0-255 for each component)
- `color_temp: value` - Color temperature in mireds
- `transition: seconds` - Transition time
- `flash: "short" | "long"` - Flash effect
- `effect: "effect_name"` - Special effect (device-dependent)

## Implementation Notes

- Uses WebSockex library for WebSocket client
- Handles Home Assistant auth flow automatically
- Message IDs are generated using `erlang:unique_integer/1`
- Requests use a synchronous call pattern with 5s timeout
- State is maintained as GenServer-style process
- Follows same exploration pattern as lutron_test.ex

## Next Steps

Once this works, you can integrate it into your main application:
1. Create a proper GenServer module for HA client
2. Add supervision tree integration
3. Add event subscription for state changes
4. Create unified lighting abstraction across Hue/Lutron/HA
