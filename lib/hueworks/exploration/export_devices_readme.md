# Device Export Tool

Export complete device information from Hue, Lutron, and Home Assistant for deduplication analysis.

## Purpose

This tool exports all device/entity information from your three lighting systems to analyze and identify duplicates (e.g., HA entities that mirror Hue bulbs or Lutron zones).

## Quick Start

```bash
iex -S mix
```

```elixir
# Export everything to exports/
Hueworks.Exploration.ExportDevices.export_all()
```

This creates three timestamped JSON files:
- `hue_devices_20260114T123456.json`
- `lutron_devices_20260114T123456.json`
- `ha_entities_20260114T123456.json`

## Individual Exports

If you want to export just one system:

```elixir
# Export only Hue
hue_data = Hueworks.Exploration.ExportDevices.export_hue()

# Export only Lutron
lutron_data = Hueworks.Exploration.ExportDevices.export_lutron()

# Export only Home Assistant
ha_data = Hueworks.Exploration.ExportDevices.export_home_assistant()
```

## What Gets Exported

### Hue Export (`hue_devices_*.json`)
- **bridges** - List of Hue bridge entries with name, host, and minimal light data (id, name, uniqueid, mac, modelid, productname, type, capabilities)
- **exported_at** - ISO8601 timestamp

### Lutron Export (`lutron_devices_*.json`)
- **lights** - Zone-controllable devices with zone_id and metadata
- **pico_buttons** - Pico button definitions with button_id and parent device
- **bridge_ip** - Bridge IP address
- **exported_at** - ISO8601 timestamp

### Home Assistant Export (`ha_entities_*.json`)
- **light_entities** - Config-only list from the entity registry, enriched with device registry info
- **light_count** - Number of light entities
- **total_entity_count** - Total entities in HA entity registry
- **host** - HA host IP
- **exported_at** - ISO8601 timestamp

## Deduplication Analysis Tips

Look for these common identifiers across systems:

### Hue → Home Assistant
- Hue lights have `uniqueid` field (e.g., `00:17:88:01:xx:xx:xx:xx-0b`)
- HA entities from Hue integration often include this in `attributes.unique_id`
- Check HA entity names against Hue light names
- Look for `attributes.via_device` in HA pointing to Hue bridge

### Lutron → Home Assistant
- Lutron zones have numeric IDs
- HA entities from Lutron integration may include zone ID in entity_id or attributes
- Match device names between systems
- Check `attributes.integration` for "lutron_caseta"

### Serial Numbers
- Hue: Check `uniqueid` or `modelid` fields
- Lutron: Check device metadata in areas/projects
- HA: Check `attributes.device_info` for manufacturer/model

### Example Deduplication Script

```elixir
# Load the exported files
hue = File.read!("/tmp/hueworks_export/hue_devices_20260114T123456.json") |> Jason.decode!()
ha = File.read!("/tmp/hueworks_export/ha_entities_20260114T123456.json") |> Jason.decode!()

# Find HA lights that are duplicates of Hue lights
hue_unique_ids =
  hue["lights"]
  |> Map.values()
  |> Enum.map(& &1["uniqueid"])
  |> MapSet.new()

duplicate_ha_entities =
  ha["light_entities"]
  |> Enum.filter(fn entity ->
    unique_id = get_in(entity, ["attributes", "unique_id"])
    unique_id && MapSet.member?(hue_unique_ids, unique_id)
  end)
  |> Enum.map(& &1["entity_id"])

IO.inspect(duplicate_ha_entities, label: "HA entities that duplicate Hue lights")
```

## File Locations

All exports are saved to: `exports/`

Files are pretty-printed JSON with 2-space indentation for easy reading.

## Next Steps

After exporting:
1. Analyze the JSON files to identify duplicate devices
2. Create a mapping of which HA entities mirror Hue/Lutron devices
3. Design a unified control layer that avoids duplicate control
4. Build scene/automation system using non-duplicate entities
