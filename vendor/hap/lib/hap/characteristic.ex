defmodule HAP.Characteristic do
  @moduledoc """
  Functions to aid in the manipulation of characteristics tuples
  """

  @typedoc """
  Represents a single characteristic consisting of a static definition, a value source,
  and (once compiled) its instance ID. Before compilation the instance ID may be omitted,
  in which case one is derived from the characteristic's position in its service.
  """
  @type t :: {module(), value_source()} | {module(), value_source(), iid() | nil}

  @typedoc """
  Represents a source for a characteristic value. May be either a static literal or
  a `{mod, opts}` tuple which is consulted when reading / writing a characteristic
  """
  @type value_source :: value() | {HAP.ValueStore.t(), value_opts: HAP.ValueStore.opts()}

  @typedoc """
  The resolved value of a characteristic
  """
  @type value :: any()

  @typedoc """
  A HAP instance ID, unique within an accessory
  """
  @type iid :: pos_integer()

  @doc false
  def compile({definition, source}, default_iid), do: {definition, source, default_iid}
  def compile({definition, source, nil}, default_iid), do: {definition, source, default_iid}

  def compile({definition, source, iid}, _default_iid) when is_integer(iid) and iid > 0,
    do: {definition, source, iid}

  @doc false
  def iid({_definition, _source, iid}), do: iid
  def iid({_definition, _source}), do: nil

  @doc false
  def value_source({_definition, source, _iid}), do: source
  def value_source({_definition, source}), do: source

  defp definition({characteristic_definition, _source, _iid}), do: characteristic_definition
  defp definition({characteristic_definition, _source}), do: characteristic_definition

  @doc false
  def get_type(characteristic), do: definition(characteristic).type()

  @doc false
  def get_perms(characteristic), do: definition(characteristic).perms()

  @doc false
  def get_format(characteristic), do: definition(characteristic).format()

  @doc false
  def get_meta(characteristic) do
    characteristic_definition = definition(characteristic)

    [
      {:format, :format},
      {:minValue, :min_value},
      {:maxValue, :max_value},
      {:minStep, :step_value},
      {:unit, :unit},
      {:maxLength, :max_length}
    ]
    |> Enum.reduce(%{}, fn {return_key, call_key}, acc ->
      if function_exported?(characteristic_definition, call_key, 0) do
        Map.put(acc, return_key, apply(characteristic_definition, call_key, []))
      else
        acc
      end
    end)
  end

  @doc false
  def get_value(characteristic, :pr) do
    characteristic_definition = definition(characteristic)

    if "pr" in characteristic_definition.perms() do
      if function_exported?(characteristic_definition, :event_only, 0) && characteristic_definition.event_only() do
        {:ok, nil}
      else
        get_value_from_source(value_source(characteristic))
      end
    else
      {:error, -70_405}
    end
  end

  def get_value(characteristic, :ev) do
    if "ev" in definition(characteristic).perms() do
      get_value_from_source(value_source(characteristic))
    else
      {:error, -70_405}
    end
  end

  @doc false
  def get_value!(characteristic, disposition) do
    {:ok, value} = get_value(characteristic, disposition)
    value
  end

  @doc false
  def put_value(characteristic, value) do
    if "pw" in definition(characteristic).perms() do
      value = maybe_cast_value(characteristic, value)
      put_value_to_source(value_source(characteristic), value)
    else
      {:error, -70_404}
    end
  end

  defp maybe_cast_value(characteristic, value) do
    case get_type(characteristic) do
      "25" -> value in [true, 1]
      _other_type -> value
    end
  end

  @doc false
  def set_change_token(characteristic, token) do
    case value_source(characteristic) do
      {mod, opts} ->
        if function_exported?(mod, :set_change_token, 2) do
          mod.set_change_token(token, opts)
        else
          {:error, -70_406}
        end

      _static ->
        raise "Cannot set change token on a statically defined characteristic"
    end
  end

  defp get_value_from_source({mod, opts}) do
    mod.get_value(opts)
  end

  defp get_value_from_source(value) do
    {:ok, value}
  end

  defp put_value_to_source({mod, opts}, value) do
    mod.put_value(value, opts)
  end

  defp put_value_to_source(_value, _new_value) do
    raise "Cannot write to a statically defined characteristic"
  end
end
